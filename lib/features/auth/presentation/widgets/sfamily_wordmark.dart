import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// "SFamily" — gradient S, solid wordmark, heart over the tail.
class SFamilyWordmark extends StatelessWidget {
  const SFamilyWordmark({super.key, this.fontSize = 46});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.neonCyan,
                  AppColors.electricBlue,
                  AppColors.neonPurple,
                  AppColors.neonPink,
                ],
              ).createShader(bounds),
              child: Text(
                'S',
                style: TextStyle(
                  fontSize: fontSize * 1.25,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  letterSpacing: -1,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              'Family',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                height: 1.0,
                letterSpacing: -0.5,
                color: AppColors.softWhite,
              ),
            ),
          ],
        ),
        Positioned(
          right: fontSize * 0.30,
          top: -fontSize * 0.12,
          child: Icon(
            Icons.favorite,
            size: fontSize * 0.30,
            color: AppColors.neonPink,
            shadows: [
              BoxShadow(
                color: AppColors.neonPink.withValues(alpha: 0.8),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
