import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Circular avatar with an initials fallback, optionally gradient-ringed.
///
/// Avatar URLs from the API are signed and expire, so a failed load is a
/// normal event rather than an error — it falls back to initials silently.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.size,
    required this.initials,
    this.imageUrl,
    this.ring = false,
    this.fontSize,
  });

  final double size;
  final String initials;
  final String? imageUrl;
  final bool ring;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.canvasRaised,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? _initials()
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initials(),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _initials(),
            ),
    );

    if (!ring) {
      return SizedBox(width: size, height: size, child: inner);
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.045),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.safeGradient,
      ),
      child: inner,
    );
  }

  Widget _initials() => Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: fontSize ?? size * 0.36,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      );
}
