import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/aurora_background.dart';
import '../../../../core/widgets/primary_button.dart';

/// Shared chrome for the auth screens: aurora background, back button and
/// the SFamily lockup, so login and register stay visually identical.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = true,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.canvas,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        // Let the aurora sit behind the keyboard rather than being squashed.
        resizeToAvoidBottomInset: true,
        body: AuroraBackground(
          child: SafeArea(
            child: CustomScrollView(
              // `onDrag` unfocuses the active field on every scroll, which
              // makes the focus ring flicker. Let the keyboard stay put.
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.manual,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 58,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Center(child: _Lockup()),
                              if (showBack)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: GlassIconButton(
                                    icon: Icons.arrow_back_rounded,
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            height: 1.15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.45,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 26),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                  sliver: SliverToBoxAdapter(child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo mark, name and promise — the same lockup as the home screen header.
class _Lockup extends StatelessWidget {
  const _Lockup();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: Image.asset(
            AppAssets.logoMark,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.diversity_3_rounded,
              size: 34,
              color: AppColors.aqua,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The gradient runs across the whole wordmark, not just the S.
            ShaderMask(
              shaderCallback: (bounds) =>
                  AppColors.safeGradient.createShader(bounds),
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'S',
                      style: TextStyle(fontSize: 31, fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: 'Family',
                      style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                style: TextStyle(
                  height: 1,
                  letterSpacing: -0.4,
                  // ShaderMask paints over this; it only needs to be opaque.
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Together. Always Safe.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "+91 ▾" picker that sits inside the phone field.
class CountryCodePicker extends StatelessWidget {
  const CountryCodePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const List<(String, String)> codes = [
    ('+91', 'India'),
    ('+1', 'USA'),
    ('+44', 'UK'),
    ('+61', 'Australia'),
    ('+971', 'UAE'),
    ('+65', 'Singapore'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          initialValue: value,
          onSelected: onChanged,
          color: AppColors.canvasRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
          itemBuilder: (_) => [
            for (final (code, country) in codes)
              PopupMenuItem(
                value: code,
                child: Text(
                  '$code   $country',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                size: 17,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
        Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 11),
          color: AppColors.glassBorder,
        ),
      ],
    );
  }
}
