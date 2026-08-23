import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Six separate boxes backed by one hidden field.
///
/// One real TextField rather than six means paste works, SMS autofill works,
/// and backspace behaves — all things a per-box implementation quietly breaks.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.length,
    required this.controller,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
  });

  final int length;
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    final text = widget.controller.text;
    if (text.length == widget.length) {
      _focus.unfocus();
      widget.onCompleted?.call(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;

    return Stack(
      children: [
        // The real field, invisible but focusable.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              showCursor: false,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => _focus.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < widget.length; i++)
                _Box(
                  digit: i < value.length ? value[i] : '',
                  active: _focus.hasFocus && i == value.length,
                  filled: i < value.length,
                  hasError: widget.hasError,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.digit,
    required this.active,
    required this.filled,
    required this.hasError,
  });

  final String digit;
  final bool active;
  final bool filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final border = hasError
        ? AppColors.alertRed
        : active
            ? AppColors.aqua
            : filled
                ? AppColors.mint.withValues(alpha: 0.6)
                : AppColors.glassBorder;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 48,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Colors.white.withValues(alpha: filled ? 0.09 : 0.045),
        border: Border.all(color: border, width: active || hasError ? 1.6 : 1),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.aqua.withValues(alpha: 0.25),
                  blurRadius: 16,
                ),
              ]
            : const [],
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
