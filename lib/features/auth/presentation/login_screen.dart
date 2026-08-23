import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_field.dart';
import '../../../core/widgets/primary_button.dart';
import 'register_screen.dart';
import 'verify_otp_screen.dart';
import '../../shell/presentation/app_shell.dart';
import 'widgets/auth_scaffold.dart';

/// Sign in.
///
/// Phone plus OTP is the primary route, matching the backend: `password` is
/// nullable on the users table. The password form is a secondary option for
/// people who set one.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Method { otp, password }

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _api = ApiClient();

  String _countryCode = '+91';
  _Method _method = _Method.otp;
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    try {
      final res = _method == _Method.otp
          ? await _requestOtp()
          : await _signInWithPassword();

      if (!mounted || res == null) return;

      if (!res.success) {
        _showErrors(res);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ask for a code, then hand off to the verification screen.
  Future<ApiResponse?> _requestOtp() async {
    final res = await _api.post('auth/otp/send', body: {
      'phone_country_code': _countryCode,
      'phone_number': _phone.text.trim(),
      'purpose': 'login',
    });

    if (!res.success || !mounted) return res;

    final otp = res.dataMap['otp'] as Map<String, dynamic>?;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VerifyOtpScreen(
        countryCode: _countryCode,
        phoneNumber: _phone.text.trim(),
        purpose: 'login',
        codeLength: (otp?['length'] as int?) ?? 6,
        resendAfter: (otp?['resend_after'] as int?) ?? 60,
        debugCode: otp?['debug_code'] as String?,
      ),
    ));

    return null;
  }

  /// Phone plus password, for users who set one.
  Future<ApiResponse?> _signInWithPassword() async {
    final res = await _api.post('auth/login', body: {
      'phone_country_code': _countryCode,
      'phone_number': _phone.text.trim(),
      'password': _password.text,
    });

    if (!res.success || !mounted) return res;

    await Session.instance.signIn(
      token: res.dataMap['token'] as String,
      user: AuthUser.fromJson(res.dataMap['user'] as Map<String, dynamic>),
    );

    if (!mounted) return null;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppShell()),
      (route) => false,
    );

    return null;
  }

  /// Surface the first field error, so the user knows which input to fix.
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
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to keep your circle connected and protected.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassCard(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MethodToggle(
                    value: _method,
                    onChanged: (m) => setState(() => _method = m),
                  ),
                  const SizedBox(height: 20),

                  GlassField(
                    label: 'Mobile number',
                    icon: Icons.phone_iphone_rounded,
                    hint: '98765 43210',
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: _method == _Method.otp
                        ? TextInputAction.done
                        : TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(15),
                    ],
                    prefix: CountryCodePicker(
                      value: _countryCode,
                      onChanged: (c) => setState(() => _countryCode = c),
                    ),
                    validator: (v) => (v == null || v.trim().length < 6)
                        ? 'Enter a valid mobile number'
                        : null,
                  ),

                  if (_method == _Method.password) ...[
                    const SizedBox(height: 16),
                    GlassField(
                      label: 'Password',
                      icon: Icons.lock_outline_rounded,
                      hint: 'Your password',
                      controller: _password,
                      obscure: true,
                      textInputAction: TextInputAction.done,
                      validator: (v) => (v == null || v.length < 8)
                          ? 'At least 8 characters'
                          : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {},
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.aqua,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: _method == _Method.otp ? 'Send OTP' : 'Sign in',
                    loading: _loading,
                    onPressed: _submit,
                  ),

                  if (_method == _Method.otp) ...[
                    const SizedBox(height: 12),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 12, color: AppColors.textMuted),
                        SizedBox(width: 5),
                        Text(
                          'We will text you a 6-digit code',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 22),
            const _OrDivider(),
            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: _SocialButton(
                    icon: Icons.g_mobiledata_rounded,
                    label: 'Google',
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SocialButton(
                    icon: Icons.apple_rounded,
                    label: 'Apple',
                    onTap: () {},
                  ),
                ),
              ],
            ),

            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'New to SFamily?',
                  style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.mint,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text(
                    'Create an account',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented control switching between OTP and password sign-in.
class _MethodToggle extends StatelessWidget {
  const _MethodToggle({required this.value, required this.onChanged});

  final _Method value;
  final ValueChanged<_Method> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          _tab(context, _Method.otp, 'OTP'),
          _tab(context, _Method.password, 'Password'),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, _Method method, String label) {
    final selected = method == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(method),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: selected ? AppColors.safeGradient : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF04121F) : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppColors.glassBorder, height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or continue with',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        Expanded(child: Divider(color: AppColors.glassBorder, height: 1)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 16,
      blur: 14,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
