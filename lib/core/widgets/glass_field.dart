import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A frosted text field.
///
/// Focus is signalled by the border and icon picking up the accent colour,
/// plus a soft outer glow — the same language as the buttons.
class GlassField extends StatefulWidget {
  const GlassField({
    super.key,
    required this.label,
    required this.icon,
    this.controller,
    this.hint,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.obscure = false,
    this.optional = false,
    this.prefix,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onChanged,
  });

  final String label;
  final IconData icon;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final bool optional;

  /// Widget shown between the icon and the input — the country-code picker
  /// on the phone field, for instance.
  final Widget? prefix;

  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  final _focus = FocusNode();
  late bool _obscured = widget.obscure;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Row(
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: AppColors.textMuted,
                ),
              ),
              if (widget.optional)
                const Text(
                  '  ·  optional',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF5C6880)),
                ),
            ],
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: AppColors.aqua.withValues(alpha: 0.22),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          // No BackdropFilter here on purpose. These fields sit inside a
          // GlassCard that already blurs its backdrop, and nesting one blur
          // inside another repaints badly while scrolling. A translucent
          // fill over the already-frosted card reads the same.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withValues(alpha: _focused ? 0.09 : 0.055),
                  border: Border.all(
                    color: _focused
                        ? AppColors.aqua.withValues(alpha: 0.75)
                        : AppColors.glassBorder,
                    width: _focused ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 15, right: 11),
                      child: Icon(
                        widget.icon,
                        size: 19,
                        color: _focused
                            ? AppColors.aqua
                            : AppColors.textMuted.withValues(alpha: 0.85),
                      ),
                    ),
                    if (widget.prefix != null) widget.prefix!,
                    Expanded(
                      child: TextFormField(
                        controller: widget.controller,
                        focusNode: _focus,
                        obscureText: _obscured,
                        keyboardType: widget.keyboardType,
                        textInputAction: widget.textInputAction,
                        inputFormatters: widget.inputFormatters,
                        textCapitalization: widget.textCapitalization,
                        validator: widget.validator,
                        onChanged: widget.onChanged,
                        cursorColor: AppColors.aqua,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          hintStyle: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textMuted.withValues(alpha: 0.55),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 18),
                          errorStyle: const TextStyle(height: 0, fontSize: 0),
                        ),
                      ),
                    ),
                    if (widget.obscure)
                      IconButton(
                        onPressed: () => setState(() => _obscured = !_obscured),
                        icon: Icon(
                          _obscured
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 19,
                          color: AppColors.textMuted,
                        ),
                      )
                    else
                      const SizedBox(width: 14),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
