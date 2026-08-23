import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Opens Material's date picker wearing the SFamily palette.
///
/// Theming it here rather than globally keeps the app's single dark theme
/// clean, and means the calendar cannot drift from the brand when the theme
/// is edited for something else.
Future<DateTime?> showSFamilyDatePicker({
  required BuildContext context,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String helpText = 'Date of birth',
}) {
  final now = DateTime.now();

  return showDatePicker(
    context: context,
    initialDate: initialDate ?? DateTime(now.year - 25, now.month, now.day),
    firstDate: firstDate ?? DateTime(1900),
    lastDate: lastDate ?? now,
    helpText: helpText,
    // Start on the year grid: scrolling back 25 years a month at a time is
    // a genuinely bad way to enter a birthday.
    initialDatePickerMode: DatePickerMode.year,
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.mint,
            onPrimary: Color(0xFF04121F),
            surface: AppColors.canvasRaised,
            onSurface: AppColors.textPrimary,
            surfaceContainerHigh: AppColors.canvasRaised,
            secondary: AppColors.aqua,
            onSecondary: Color(0xFF04121F),
            outline: AppColors.glassBorder,
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: AppColors.canvasRaised,
            headerBackgroundColor: AppColors.barSurface,
            headerForegroundColor: AppColors.textPrimary,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
              side: const BorderSide(color: AppColors.glassBorder),
            ),
            dayForegroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF04121F)
                  : AppColors.textPrimary,
            ),
            dayBackgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColors.mint
                  : Colors.transparent,
            ),
            todayForegroundColor:
                const WidgetStatePropertyAll(AppColors.aqua),
            todayBorder: const BorderSide(color: AppColors.aqua),
            yearForegroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF04121F)
                  : AppColors.textPrimary,
            ),
            yearBackgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColors.mint
                  : Colors.transparent,
            ),
            weekdayStyle: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            dividerColor: AppColors.glassBorder,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.mint),
          ),
        ),
        child: child!,
      );
    },
  );
}

/// A read-only field that opens the themed calendar when tapped.
class DateOfBirthField extends StatelessWidget {
  const DateOfBirthField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _formatted => value == null
      ? 'Select your date of birth'
      : '${value!.day} ${_months[value!.month - 1]} ${value!.year}';

  int? get _age {
    if (value == null) return null;
    final now = DateTime.now();
    var age = now.year - value!.year;
    if (now.month < value!.month ||
        (now.month == value!.month && now.day < value!.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final set = value != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 7),
          child: Text(
            'Date of birth',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: AppColors.textMuted,
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final picked = await showSFamilyDatePicker(
              context: context,
              initialDate: value,
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.055),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.cake_outlined,
                    size: 19, color: AppColors.textMuted),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    _formatted,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: set
                          ? AppColors.textPrimary
                          : AppColors.textMuted.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                if (_age != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: AppColors.mint.withValues(alpha: 0.13),
                    ),
                    child: Text(
                      '$_age yrs',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mint,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more_rounded,
                    size: 19, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
