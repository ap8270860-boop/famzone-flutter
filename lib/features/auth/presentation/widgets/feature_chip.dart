import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// One of the small glowing capability tiles orbiting the logo.
class FeatureChipData {
  const FeatureChipData({
    required this.label,
    required this.icon,
    required this.tint,
    this.asset,
    this.dx = 0,
  });

  final String label;
  final IconData icon;
  final Color tint;

  /// Optional artwork. When set it replaces [icon] — use it once real
  /// per-feature illustrations exist.
  final String? asset;

  /// Horizontal nudge, so a column of chips can follow a gentle arc.
  final double dx;
}

class FeatureChip extends StatelessWidget {
  const FeatureChip({
    super.key,
    required this.data,
    required this.glow,
  });

  final FeatureChipData data;

  /// 0..1 — drives the breathing glow, shared across every chip.
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(data.dx, 0),
      child: Container(
        width: 66,
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              data.tint.withValues(alpha: 0.30),
              AppColors.royalNavy.withValues(alpha: 0.55),
            ],
          ),
          border: Border.all(
            color: data.tint.withValues(alpha: 0.70),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: data.tint.withValues(alpha: 0.20 + 0.22 * glow),
              blurRadius: 14 + 8 * glow,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (data.asset != null)
              Image.asset(data.asset!, width: 24, height: 24)
            else
              Icon(data.icon, size: 23, color: AppColors.softWhite),
            const SizedBox(height: 4),
            Text(
              data.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 7.5,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: AppColors.softWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
