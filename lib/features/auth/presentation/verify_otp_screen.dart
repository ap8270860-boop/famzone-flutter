import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../shell/presentation/app_shell.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/otp_input.dart';

/// Enter the code sent to the user's phone.
class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({
    super.key,
    required this.countryCode,
    required this.phoneNumber,
    required this.purpose,
    this.codeLength = 6,
    this.resendAfter = 60,
    this.debugCode,
  });

  final String countryCode;
  final String phoneNumber;

  /// 'registration' or 'login' — passed straight back to the API.
  final String purpose;

  final int codeLength;
  final int resendAfter;

  /// Present only while no SMS provider is connected: the API echoes the code
  /// back so it can be shown on screen. Never populated in production.
  final String? debugCode;

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final _api = ApiClient();
  final _code = TextEditingController();

  Timer? _timer;
  int _secondsLeft = 0;
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  String? _debugCode;

  @override
  void initState() {
    super.initState();
    _debugCode = widget.debugCode;
    _startCountdown(widget.resendAfter);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _api.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        if (mounted) setState(() => _secondsLeft = 0);
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _verify([String? code]) async {
    final entered = code ?? _code.text;
    if (entered.length != widget.codeLength) {
      setState(() => _error = 'Enter all ${widget.codeLength} digits');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final res = await _api.post('auth/otp/verify', body: {
        'phone_country_code': widget.countryCode,
        'phone_number': widget.phoneNumber,
        'code': entered,
        'purpose': widget.purpose,
      });

      if (!mounted) return;

      if (res.success) {
        await Session.instance.signIn(
          token: res.dataMap['token'] as String,
          user: AuthUser.fromJson(res.dataMap['user'] as Map<String, dynamic>),
        );

        if (!mounted) return;

        // Clear the whole auth stack — there is nothing to go back to.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppShell()),
          (route) => false,
        );
        return;
      } else {
        setState(() => _error = res.message);
        _code.clear();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;

    setState(() {
      _resending = true;
      _error = null;
    });

    try {
      final res = await _api.post('auth/otp/send', body: {
        'phone_country_code': widget.countryCode,
        'phone_number': widget.phoneNumber,
        'purpose': widget.purpose,
      });

      if (!mounted) return;

      if (res.success) {
        final otp = res.dataMap['otp'] as Map<String, dynamic>?;
        setState(() => _debugCode = otp?['debug_code'] as String?);
        _code.clear();
        _startCountdown((otp?['resend_after'] as int?) ?? widget.resendAfter);
        _snack('A new code is on its way.');
      } else {
        setState(() => _error = res.message);
        // The API tells us how long to wait when it refuses.
        final retry = (res.errors is Map)
            ? (res.errors as Map)['retry_after'] as int?
            : null;
        if (retry != null) _startCountdown(retry);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
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
    final phone = '${widget.countryCode} ${widget.phoneNumber}';

    return AuthScaffold(
      title: 'Verify your number',
      subtitle: 'We sent a ${widget.codeLength}-digit code to $phone.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_debugCode != null) _DebugCodeCard(code: _debugCode!),
          if (_debugCode != null) const SizedBox(height: 16),

          GlassCard(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OtpInput(
                  length: widget.codeLength,
                  controller: _code,
                  hasError: _error != null,
                  enabled: !_verifying,
                  onCompleted: _verify,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 15, color: AppColors.alertRed),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.alertRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Verify',
                  loading: _verifying,
                  onPressed: _verify,
                ),

                const SizedBox(height: 18),
                Center(
                  child: _secondsLeft > 0
                      ? Text(
                          'Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        )
                      : TextButton.icon(
                          onPressed: _resending ? null : _resend,
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                          label: Text(
                            _resending ? 'Sending…' : 'Resend code',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.mint,
                          ),
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
              child: const Text(
                'Wrong number? Go back',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the code returned by the API while no SMS provider is connected.
///
/// The API only populates `debug_code` outside production, so this card
/// cannot appear for a real user.
class _DebugCodeCard extends StatelessWidget {
  const _DebugCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: AppColors.warmGold,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.construction_rounded,
              size: 20, color: AppColors.warmGold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No SMS provider yet',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warmGold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 7,
                    color: AppColors.textPrimary,
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
