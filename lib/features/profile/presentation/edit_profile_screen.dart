import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/widgets/account_type_picker.dart';
import '../../people/presentation/connections_screen.dart';
import '../../auth/presentation/widgets/auth_scaffold.dart';
import '../data/profile_api.dart';
import 'widgets/avatar_picker.dart';
import 'widgets/change_password_sheet.dart';
import 'widgets/section_card.dart';
import 'widgets/themed_date_picker.dart';
import 'widgets/username_field.dart';

/// Edit everything about the signed-in user.
///
/// Only changed fields are sent — the endpoint patches rather than replaces,
/// so an untouched field is never overwritten by a stale value the screen
/// happened to be holding.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _api = ProfileApi();

  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _about = TextEditingController();
  final _emergency = TextEditingController();

  Map<String, dynamic> _original = {};

  DateTime? _dob;
  String? _gender;
  bool _showLastSeen = true;
  bool _showOnline = true;
  bool _showReceipts = true;
  bool _allowInvites = true;
  bool _isPrivate = false;

  AccountType _accountType = AccountType.adult;
  EducationStage _stage = EducationStage.school;

  int _followers = 0;
  int _following = 0;
  int _familyCount = 0;
  bool _useAlternateAvatar = false;

  String? _avatarUrl;
  String? _alternateAvatarUrl;
  File? _pendingAvatar;
  File? _pendingAlternate;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPrimary = false;
  bool _uploadingAlternate = false;
  UsernameStatus? _usernameStatus;

  static const _genders = {
    'male': 'Male',
    'female': 'Female',
    'other': 'Other',
    'prefer_not_to_say': 'Prefer not to say',
  };


  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _about.dispose();
    _emergency.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.fetch();
      if (!mounted) return;

      if (res.success) {
        _apply(res.dataMap);
      } else {
        _snack(res.message);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply(Map<String, dynamic> data) {
    final privacy = data['privacy'] as Map<String, dynamic>? ?? const {};

    setState(() {
      _name.text = data['name'] as String? ?? '';
      _username.text = data['username'] as String? ?? '';
      _email.text = data['email'] as String? ?? '';
      _about.text = data['about'] as String? ?? '';
      _emergency.text = privacy['emergency_message'] as String? ?? '';

      final dob = data['date_of_birth'] as String?;
      _dob = dob == null ? null : DateTime.tryParse(dob);

      _gender = data['gender'] as String?;

      _showLastSeen = privacy['show_last_seen'] as bool? ?? true;
      _showOnline = privacy['show_online_status'] as bool? ?? true;
      _showReceipts = privacy['show_read_receipts'] as bool? ?? true;
      _allowInvites = privacy['allow_group_invites'] as bool? ?? true;
      _isPrivate = privacy['is_private'] as bool? ?? false;

      _accountType = _typeFrom(data['user_type'] as String?);
      _stage = (data['education_stage'] as String?) == 'college'
          ? EducationStage.college
          : EducationStage.school;

      final counts = data['counts'] as Map<String, dynamic>? ?? const {};
      _followers = counts['followers'] as int? ?? 0;
      _following = counts['following'] as int? ?? 0;
      _familyCount = counts['family'] as int? ?? 0;

      _avatarUrl = data['avatar_url'] as String?;
      _alternateAvatarUrl = data['alternate_avatar_url'] as String?;
      _useAlternateAvatar = data['use_alternate_avatar'] as bool? ?? false;

      _original = _snapshot();
    });
  }

  static AccountType _typeFrom(String? value) => switch (value) {
        'kid' => AccountType.kid,
        'senior' => AccountType.senior,
        _ => AccountType.adult,
      };

  void _openConnections(ConnectionsTab tab) {
    final me = Session.instance.user;

    if (me == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionsScreen(
          userId: me.id,
          initialTab: tab,
          title: me.username == null ? me.name : '@${me.username}',
          counts: {
            ConnectionsTab.followers: _followers,
            ConnectionsTab.following: _following,
            ConnectionsTab.family: _familyCount,
          },
        ),
      ),
    );
  }

  /// Current form values, for diffing against what the server sent.
  Map<String, dynamic> _snapshot() => {
        'name': _name.text.trim(),
        'username': _username.text.trim().isEmpty ? null : _username.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'about': _about.text.trim().isEmpty ? null : _about.text.trim(),
        'emergency_message':
            _emergency.text.trim().isEmpty ? null : _emergency.text.trim(),
        'date_of_birth': _dob?.toIso8601String().split('T').first,
        'gender': _gender,
        'show_last_seen': _showLastSeen,
        'show_online_status': _showOnline,
        'show_read_receipts': _showReceipts,
        'allow_group_invites': _allowInvites,
        'is_private': _isPrivate,
        'use_alternate_avatar': _useAlternateAvatar,
        'user_type': _accountType.name,
        // The server rejects a stage on anything but a kid account,
        // so send null rather than a stale value.
        'education_stage':
            _accountType == AccountType.kid ? _stage.name : null,
      };

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_usernameStatus != null && !_usernameStatus!.available) {
      _snack('Pick an available username first.');
      return;
    }

    final current = _snapshot();
    final changes = <String, dynamic>{
      for (final entry in current.entries)
        if (_original[entry.key] != entry.value) entry.key: entry.value,
    };

    if (changes.isEmpty) {
      _snack('Nothing to save.');
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await _api.update(changes);
      if (!mounted) return;

      if (res.success) {
        await Session.instance
            .updateUser(AuthUser.fromJson(res.dataMap));
        if (!mounted) return;
        setState(() => _original = current);
        _snack(res.message, success: true);
        Navigator.of(context).maybePop();
      } else {
        _showErrors(res);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadAvatar(XFile file, {required bool alternate}) async {
    setState(() {
      if (alternate) {
        _pendingAlternate = File(file.path);
        _uploadingAlternate = true;
      } else {
        _pendingAvatar = File(file.path);
        _uploadingPrimary = true;
      }
    });

    try {
      final res = await _api.uploadAvatar(
        file.path,
        slot: alternate ? 'alternate' : 'primary',
      );
      if (!mounted) return;

      if (res.success) {
        final user = res.dataMap['user'] as Map<String, dynamic>;
        setState(() {
          _avatarUrl = user['avatar_url'] as String?;
          _alternateAvatarUrl = user['alternate_avatar_url'] as String?;
          _pendingAvatar = null;
          _pendingAlternate = null;
        });
        await Session.instance.updateUser(AuthUser.fromJson(user));
        if (mounted) _snack(res.message, success: true);
      } else {
        setState(() {
          _pendingAvatar = alternate ? _pendingAvatar : null;
          _pendingAlternate = alternate ? null : _pendingAlternate;
        });
        _showErrors(res);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPrimary = false;
          _uploadingAlternate = false;
        });
      }
    }
  }

  Future<void> _removeAvatar({required bool alternate}) async {
    try {
      final res = await _api.removeAvatar(
        slot: alternate ? 'alternate' : 'primary',
      );
      if (!mounted) return;

      if (res.success) {
        setState(() {
          if (alternate) {
            _alternateAvatarUrl = null;
            _pendingAlternate = null;
            _useAlternateAvatar = false;
          } else {
            _avatarUrl = null;
            _pendingAvatar = null;
          }
        });
        await Session.instance.updateUser(AuthUser.fromJson(res.dataMap));
        if (mounted) _snack(res.message, success: true);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  void _showErrors(ApiResponse res) {
    var message = res.message;
    final errors = res.errors;
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) message = first.first.toString();
    }
    _snack(message);
  }

  /// Show a message from the API at the top of the screen.
  void _snack(String message, {bool success = false}) {
    AppToast.show(
      context,
      message,
      type: success ? ToastType.success : ToastType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AuthScaffold(
        title: 'Edit profile',
        subtitle: 'Loading your details…',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(color: AppColors.mint),
          ),
        ),
      );
    }

    final initials = Session.instance.user?.initials ?? '?';

    return AuthScaffold(
      title: 'Edit profile',
      subtitle: 'Keep your details current so your circle can reach you.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CountsRow(
              followers: _followers,
              following: _following,
              family: _familyCount,
              onTap: _openConnections,
            ),
            const SizedBox(height: 14),

            _avatars(initials),
            const SizedBox(height: 18),

            SectionCard(
              title: 'About you',
              icon: Icons.badge_outlined,
              children: [
                GlassField(
                  label: 'Full name',
                  icon: Icons.person_outline_rounded,
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 16),
                UsernameField(
                  controller: _username,
                  api: _api,
                  initialUsername: _original['username'] as String?,
                  onStatusChanged: (s) => _usernameStatus = s,
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: 'About',
                  icon: Icons.notes_rounded,
                  hint: 'A short line about you',
                  controller: _about,
                  optional: true,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: 'Personal',
              icon: Icons.cake_outlined,
              tint: AppColors.neonPink,
              subtitle: 'Used on your SOS card and by your family.',
              children: [
                DateOfBirthField(
                  value: _dob,
                  onChanged: (d) => setState(() => _dob = d),
                ),
                const SizedBox(height: 18),
                ChipSelect<String>(
                  label: 'Gender',
                  optional: true,
                  options: _genders,
                  value: _gender,
                  onChanged: (v) => setState(() => _gender = v),
                ),
              ],
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: 'Contact',
              icon: Icons.mail_outline_rounded,
              tint: AppColors.warmGold,
              subtitle: 'Changing your email means verifying it again.',
              children: [
                GlassField(
                  label: 'Email',
                  icon: Icons.alternate_email_rounded,
                  hint: 'you@example.com',
                  controller: _email,
                  optional: true,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(v.trim())
                        ? null
                        : 'That email does not look right';
                  },
                ),
                const SizedBox(height: 16),
                _PhoneRow(phone: Session.instance.user?.phone ?? ''),
              ],
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: 'Safety',
              icon: Icons.emergency_outlined,
              tint: AppColors.alertRed,
              subtitle: 'Sent with every SOS alert you raise.',
              children: [
                GlassField(
                  label: 'Emergency message',
                  icon: Icons.sos_rounded,
                  hint: 'I need help, please check on me.',
                  controller: _emergency,
                  optional: true,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: 'Account type',
              icon: Icons.badge_outlined,
              tint: AppColors.warmGold,
              subtitle:
                  'Changes what SFamily expects of this account. A child '
                  'account is watched over by the family it belongs to.',
              children: [
                AccountTypePicker(
                  type: _accountType,
                  stage: _stage,
                  onTypeChanged: (t) => setState(() => _accountType = t),
                  onStageChanged: (v) => setState(() => _stage = v),
                ),
              ],
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: 'Privacy',
              icon: Icons.lock_outline_rounded,
              tint: AppColors.neonPurple,
              children: [
                SettingSwitch(
                  title: 'Private account',
                  subtitle: _isPrivate
                      ? 'People must ask to follow you, and only accepted '
                          'followers see your profile.'
                      : 'Anyone can follow you and see your profile. Turning '
                          'this on will not remove existing followers.',
                  value: _isPrivate,
                  onChanged: (v) => setState(() => _isPrivate = v),
                ),
                SettingSwitch(
                  title: 'Show last seen',
                  subtitle: 'Your circle can see when you were last active.',
                  value: _showLastSeen,
                  onChanged: (v) => setState(() => _showLastSeen = v),
                ),
                SettingSwitch(
                  title: 'Show online status',
                  subtitle: 'A green dot while you have the app open.',
                  value: _showOnline,
                  onChanged: (v) => setState(() => _showOnline = v),
                ),
                SettingSwitch(
                  title: 'Read receipts',
                  subtitle: 'Others see when you have read their messages.',
                  value: _showReceipts,
                  onChanged: (v) => setState(() => _showReceipts = v),
                ),
                SettingSwitch(
                  title: 'Allow group invites',
                  subtitle: 'Let people add you to circles directly.',
                  value: _allowInvites,
                  onChanged: (v) => setState(() => _allowInvites = v),
                ),
              ],
            ),
            const SizedBox(height: 22),

            PrimaryButton(
              label: 'Save changes',
              loading: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: 12),

            _ChangePasswordLink(api: _api),
          ],
        ),
      ),
    );
  }

  Widget _avatars(String initials) {
    return SectionCard(
      title: 'Photos',
      icon: Icons.photo_camera_outlined,
      tint: AppColors.mint,
      subtitle: 'A second photo can stand in for people outside your circle.',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AvatarPicker(
              imageUrl: _avatarUrl,
              localFile: _pendingAvatar,
              initials: initials,
              busy: _uploadingPrimary,
              label: 'Profile photo\nYour circle sees this',
              onPicked: (f) => _uploadAvatar(f, alternate: false),
              onRemoved: () => _removeAvatar(alternate: false),
            ),
            AvatarPicker(
              imageUrl: _alternateAvatarUrl,
              localFile: _pendingAlternate,
              initials: initials,
              busy: _uploadingAlternate,
              accent: AppColors.warmGold,
              label: 'Security photo\nEveryone else sees this',
              onPicked: (f) => _uploadAvatar(f, alternate: true),
              onRemoved: () => _removeAvatar(alternate: true),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SettingSwitch(
          title: 'Use security photo publicly',
          subtitle: _alternateAvatarUrl == null
              ? 'Add a security photo first.'
              : 'People outside your circles see the security photo instead '
                  'of your real one.',
          value: _useAlternateAvatar,
          onChanged: _alternateAvatarUrl == null
              ? (_) {}
              : (v) => setState(() => _useAlternateAvatar = v),
        ),
      ],
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_iphone_rounded,
              size: 19, color: AppColors.textMuted),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mobile number',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.mint.withValues(alpha: 0.13),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 12, color: AppColors.mint),
                SizedBox(width: 4),
                Text(
                  'Verified',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.mint,
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

class _ChangePasswordLink extends StatelessWidget {
  const _ChangePasswordLink({required this.api});

  final ProfileApi api;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ChangePasswordSheet(api: api),
      ),
      icon: const Icon(Icons.key_rounded, size: 17),
      label: const Text(
        'Change password',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.aqua,
        minimumSize: const Size.fromHeight(50),
      ),
    );
  }
}

/// Followers, following and family, straight from the profile payload.
class _CountsRow extends StatelessWidget {
  const _CountsRow({
    required this.followers,
    required this.following,
    required this.family,
    this.onTap,
  });

  final int followers;
  final int following;
  final int family;

  /// Opens the matching list. Each cell is its own tap target rather than the
  /// whole card, so tapping "Family" does not land you on Followers.
  final void Function(ConnectionsTab tab)? onTap;

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label, ConnectionsTab tab) =>
        Expanded(
          child: GestureDetector(
            onTap: onTap == null ? null : () => onTap!(tab),
            behavior: HitTestBehavior.opaque,
            child: Column(
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            ),
          ),
        );

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 18),
      radius: 18,
      child: Row(
        children: [
          cell('$followers', 'Followers', ConnectionsTab.followers),
          cell('$following', 'Following', ConnectionsTab.following),
          cell('$family', 'Family', ConnectionsTab.family),
        ],
      ),
    );
  }
}
