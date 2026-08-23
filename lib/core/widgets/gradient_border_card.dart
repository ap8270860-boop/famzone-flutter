import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A card whose outline is a gradient stroke.
///
/// Built as a gradient-filled box with a solid inner box inset by the stroke
/// width — Flutter's Border cannot take a gradient directly, and a
/// CustomPainter would be heavier than this needs to be.
class GradientBorderCard extends StatelessWidget {
  const GradientBorderCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 22,
    this.strokeWidth = 1.4,
    this.gradient,
    this.fill,
    this.glow = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double strokeWidth;
  final Gradient? gradient;
  final Color? fill;
  final bool glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stroke = gradient ??
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.aqua, AppColors.mint, Color(0x3329D3E8)],
          stops: [0.0, 0.45, 1.0],
        );

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: stroke,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: AppColors.aqua.withValues(alpha: 0.14),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      padding: EdgeInsets.all(strokeWidth),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius - strokeWidth),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              fill ?? const Color(0xFF04304F),
              fill ?? const Color(0xFF02203A),
            ],
          ),
        ),
        padding: padding,
        child: child,
      ),
    );

    if (onTap == null) return card;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}

/// Paints an icon with the brand gradient instead of a flat colour.
class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, this.size = 24, this.gradient});

  final IconData icon;
  final double size;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          (gradient ?? AppColors.safeGradient).createShader(bounds),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}
