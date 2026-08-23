import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A frosted surface.
///
/// Three layers make it read as glass rather than as a grey box: a real
/// backdrop blur, a translucent fill, and a hairline border that is brighter
/// at the top-left than the bottom-right — the way light catches an edge.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.blur = 22,
    this.tint,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  /// Optional accent wash, for cards that carry a status colour.
  final Color? tint;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (tint ?? Colors.white).withValues(alpha: tint == null ? 0.10 : 0.16),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
            border: Border.all(color: AppColors.glassBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          // Only wrap in Material/InkWell when the card is genuinely
          // tappable. Otherwise the Material becomes the surface that every
          // nested button's ink splash paints onto, which reads as a flash
          // across the whole card.
          child: onTap == null
              ? Padding(padding: padding, child: child)
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: borderRadius,
                    child: Padding(padding: padding, child: child),
                  ),
                ),
        ),
      ),
    );
  }
}
