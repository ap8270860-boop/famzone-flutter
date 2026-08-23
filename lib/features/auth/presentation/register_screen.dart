import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';
import 'login_screen.dart';
import 'verify_otp_screen.dart';
import 'widgets/auth_scaffold.dart';

/// Create an account.
///
/// Fields mirror what the users table actually requires at signup: name and
/// phone. Email and referral code are genuinely optional, and the password is
/// too — OTP is the credential. Everything else (avatar, blood group, privacy
/// toggles) is collected later during onboarding rather than gating signup.
// Signup asks for the minimum that makes an account work: name, number,
// optional email. The account type moved to the profile — it is not
// needed to create the account, and every field on this screen is a
// chance for somebody to abandon it.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _referral = TextEditingController();
  final _api = ApiClient();

  String _countryCode = '+91';
  bool _agreed = false;
  bool _loading = false;
  bool _showReferral = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _referral.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_agreed) {
      _snack('Please accept the Terms and Privacy Policy to continue.');
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await _api.post('auth/register', body: {
        'name': _name.text.trim(),
        'phone_country_code': _countryCode,
        'phone_number': _phone.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        if (_referral.text.trim().isNotEmpty)
          'referral_code': _referral.text.trim().toUpperCase(),
        'device_type': 'android',
      });

      if (!mounted) return;

      if (res.success) {
        final otp = res.dataMap['otp'] as Map<String, dynamic>?;

        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VerifyOtpScreen(
            countryCode: _countryCode,
            phoneNumber: _phone.text.trim(),
            purpose: 'registration',
            codeLength: (otp?['length'] as int?) ?? 6,
            resendAfter: (otp?['resend_after'] as int?) ?? 60,
            debugCode: otp?['debug_code'] as String?,
          ),
        ));
      } else {
        _showErrors(res);
      }
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Surface the first field error the API returned, so the user is told
  /// which input to fix rather than just "invalid".
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
      title: 'Create your circle',
      subtitle: 'A minute to set up, and your family is protected.',
      showBack: false,
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
                  GlassField(
                    label: 'Full name',
                    icon: Icons.person_outline_rounded,
                    hint: 'Abhishek Sharma',
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Tell us your name'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  GlassField(
                    label: 'Mobile number',
                    icon: Icons.phone_iphone_rounded,
                    hint: '98765 43210',
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
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
                  const SizedBox(height: 16),

                  GlassField(
                    label: 'Email',
                    icon: Icons.alternate_email_rounded,
                    hint: 'you@example.com',
                    controller: _email,
                    optional: true,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(v.trim());
                      return ok ? null : 'That email does not look right';
                    },
                  ),

                  if (_showReferral) ...[
                    const SizedBox(height: 16),
                    GlassField(
                      label: 'Referral code',
                      icon: Icons.card_giftcard_rounded,
                      hint: 'ABCD2345',
                      controller: _referral,
                      optional: true,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(12),
                        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                      ],
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showReferral = true),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text(
                          'Have a referral code?',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.aqua,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),

                  const SizedBox(height: 6),
                  _TermsCheckbox(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v),
                  ),

                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Create account',
                    loading: _loading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const _TrustStrip(),

            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Already have an account?',
                  style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.mint,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text(
                    'Sign in',
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

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // GestureDetector, not InkWell: an ink splash here paints onto the
    // enclosing card's Material and flashes behind the whole row. The
    // checkbox's own fill animation is the feedback.
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: value ? AppColors.safeGradient : null,
                color: value ? null : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: value ? Colors.transparent : AppColors.glassBorder,
                ),
              ),
              child: value
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Color(0xFF04121F))
                  : null,
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textMuted,
                  ),
                  children: [
                    TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(
                        color: AppColors.aqua,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        color: AppColors.aqua,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three reassurances, because handing over a phone number and a location
/// permission is a real ask.
class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  static const List<(IconData, String)> _items = [
    (Icons.lock_rounded, 'Private by default'),
    (Icons.groups_rounded, 'Only your circle'),
    (Icons.bolt_rounded, 'Instant SOS'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (icon, label) in _items)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.mint.withValues(alpha: 0.12),
                  border: Border.all(
                    color: AppColors.mint.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(icon, size: 17, color: AppColors.mint),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
