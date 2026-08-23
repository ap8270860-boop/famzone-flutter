import 'package:flutter/material.dart';

import '../../../../core/api/api_response.dart';
import '../../../../core/session/session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/glass_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/profile_api.dart';

/// Set or change the account password.
///
/// The current password is only asked for when one already exists — an
/// OTP-only account is adding a password, not replacing one.
class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key, required this.api});

  final ProfileApi api;

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _saving = false;

  /// Whether this account already has a password to verify against.
  bool get _hasPassword => Session.instance.user?.hasPassword ?? false;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Rough strength, purely to give the user feedback while typing. The real
  /// rules are enforced server-side.
  ({double score, String label, Color colour}) get _strength {
    final value = _password.text;
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value)) {
      score++;
    }
    if (RegExp(r'\d').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;

    return switch (score) {
      0 || 1 => (score: 0.2, label: 'Weak', colour: AppColors.alertRed),
      2 || 3 => (score: 0.55, label: 'Fair', colour: AppColors.warmGold),
      4 => (score: 0.8, label: 'Good', colour: AppColors.aqua),
      _ => (score: 1.0, label: 'Strong', colour: AppColors.mint),
    };
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      final res = await widget.api.changePassword(
        currentPassword: _hasPassword ? _current.text : null,
        password: _password.text,
        confirmation: _confirm.text,
      );

      if (!mounted) return;

      if (res.success) {
        // Toast before popping: it lives in the root overlay, so it
        // stays on screen once this sheet is gone.
        AppToast.success(context, res.message);
        Navigator.of(context).pop();
      } else {
        var message = res.message;
        final errors = res.errors;
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          if (first is List && first.isNotEmpty) {
            message = first.first.toString();
          }
        }
        _snack(message);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    final strength = _strength;

    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.canvasRaised,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: AppColors.glassBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    _hasPassword ? 'Change password' : 'Set a password',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _hasPassword
                        ? 'Your other devices will be signed out.'
                        : 'Adds a second way in, alongside your OTP.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 22),

                  if (_hasPassword) ...[
                    GlassField(
                      label: 'Current password',
                      icon: Icons.lock_outline_rounded,
                      controller: _current,
                      obscure: true,
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your current password'
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  GlassField(
                    label: 'New password',
                    icon: Icons.key_rounded,
                    hint: 'At least 8 characters',
                    controller: _password,
                    obscure: true,
                    validator: (v) => (v == null || v.length < 8)
                        ? 'At least 8 characters'
                        : null,
                  ),

                  if (_password.text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: strength.score,
                              minHeight: 5,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.07),
                              valueColor:
                                  AlwaysStoppedAnimation(strength.colour),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          strength.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: strength.colour,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  GlassField(
                    label: 'Confirm new password',
                    icon: Icons.check_circle_outline_rounded,
                    controller: _confirm,
                    obscure: true,
                    validator: (v) =>
                        v != _password.text ? 'The passwords do not match' : null,
                  ),

                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _hasPassword ? 'Update password' : 'Set password',
                    loading: _saving,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
