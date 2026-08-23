import 'package:flutter/material.dart';

import 'app_colors.dart';

/// App-wide theming.
///
/// SFamily is dark-first — the palette has no light variant, so the app
/// pins itself to dark rather than following the system setting.
abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.electricBlue,
      onPrimary: AppColors.softWhite,
      secondary: AppColors.neonCyan,
      onSecondary: AppColors.deepNavy,
      tertiary: AppColors.neonPurple,
      onTertiary: AppColors.softWhite,
      surface: AppColors.deepNavy,
      onSurface: AppColors.softWhite,
      surfaceContainerHighest: AppColors.royalNavy,
      onSurfaceVariant: AppColors.lavenderGray,
      outline: Color(0xFF2A3565),
      error: AppColors.neonPink,
      onError: AppColors.softWhite,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.deepNavy,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.softWhite,
        displayColor: AppColors.softWhite,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.electricBlue,
          foregroundColor: AppColors.softWhite,
          disabledBackgroundColor: AppColors.royalNavy,
          disabledForegroundColor: AppColors.lavenderGray,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.softWhite,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: Color(0xFF2A3565), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.neonCyan),
      ),
    );
  }
}
