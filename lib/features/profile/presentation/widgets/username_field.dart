import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_field.dart';
import '../../data/profile_api.dart';

/// Username input that checks availability while you type.
///
/// Three things make this behave rather than thrash the API: a debounce, a
/// request generation counter so a slow reply cannot overwrite a newer one,
/// and a local format check that short-circuits obviously invalid input
/// before any network call happens.
class UsernameField extends StatefulWidget {
  const UsernameField({
    super.key,
    required this.controller,
    required this.api,
    this.initialUsername,
    this.onStatusChanged,
  });

  final TextEditingController controller;
  final ProfileApi api;

  /// The name the user already holds, so it never reads as taken.
  final String? initialUsername;

  final ValueChanged<UsernameStatus?>? onStatusChanged;

  @override
  State<UsernameField> createState() => _UsernameFieldState();
}

enum _Check { idle, tooShort, checking, ok, taken, invalid }

class _UsernameFieldState extends State<UsernameField> {
  static const _debounce = Duration(milliseconds: 450);
  static const _minLength = 3;

  Timer? _timer;
  int _generation = 0;

  _Check _state = _Check.idle;
  String _message = '';
  List<String> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _timer?.cancel();

    final value = widget.controller.text.trim().toLowerCase();

    if (value.isEmpty) {
      _set(_Check.idle, '');
      widget.onStatusChanged?.call(null);
      return;
    }

    if (value == widget.initialUsername) {
      _set(_Check.ok, 'This is your current username.');
      widget.onStatusChanged?.call(null);
      return;
    }

    if (value.length < _minLength) {
      _set(_Check.tooShort, 'At least $_minLength characters.');
      widget.onStatusChanged?.call(null);
      return;
    }

    // Catch bad formats locally — no point spending a request to be told
    // what we already know.
    if (!RegExp(r'^[a-z][a-z0-9._]*$').hasMatch(value)) {
      _set(_Check.invalid,
          'Start with a letter, then letters, numbers, dots or underscores.');
      widget.onStatusChanged?.call(null);
      return;
    }

    _set(_Check.checking, 'Checking availability…');
    _timer = Timer(_debounce, () => _check(value));
  }

  Future<void> _check(String value) async {
    final generation = ++_generation;

    try {
      final status = await widget.api.checkUsername(value);

      // A reply for an older keystroke must not overwrite a newer state.
      if (!mounted || generation != _generation) return;

      setState(() {
        _state = status.available ? _Check.ok : _Check.taken;
        _message = status.message;
        _suggestions = status.suggestions;
      });
      widget.onStatusChanged?.call(status);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _set(_Check.idle, '');
      widget.onStatusChanged?.call(null);
    }
  }

  void _set(_Check state, String message) {
    if (!mounted) return;
    setState(() {
      _state = state;
      _message = message;
      _suggestions = const [];
    });
  }

  Color get _tint => switch (_state) {
        _Check.ok => AppColors.mint,
        _Check.taken || _Check.invalid => AppColors.alertRed,
        _Check.tooShort => AppColors.warmGold,
        _ => AppColors.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassField(
          label: 'Username',
          icon: Icons.alternate_email_rounded,
          hint: 'abhishek',
          controller: widget.controller,
          optional: true,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            LengthLimitingTextInputFormatter(32),
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9._]')),
            // Store lowercase regardless of how it was typed.
            TextInputFormatter.withFunction(
              (_, next) => next.copyWith(text: next.text.toLowerCase()),
            ),
          ],
        ),
        if (_state != _Check.idle) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                if (_state == _Check.checking)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: AppColors.textMuted,
                    ),
                  )
                else
                  Icon(
                    _state == _Check.ok
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 14,
                    color: _tint,
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _message,
                    style: TextStyle(fontSize: 12, color: _tint),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _suggestions)
                GestureDetector(
                  onTap: () {
                    widget.controller.text = s;
                    widget.controller.selection =
                        TextSelection.collapsed(offset: s.length);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: AppColors.aqua.withValues(alpha: 0.10),
                      border: Border.all(
                        color: AppColors.aqua.withValues(alpha: 0.40),
                      ),
                    ),
                    child: Text(
                      '@$s',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.aqua,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
