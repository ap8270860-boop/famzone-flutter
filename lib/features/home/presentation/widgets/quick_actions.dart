import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/gradient_border_card.dart';

/// The four shortcuts under the status card.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key, this.onTap});

  final void Function(String key)? onTap;

  static const _items = <(String, IconData, String, Color)>[
    ('sos', Icons.sos_rounded, 'Smart SOS', AppColors.mint),
    ('location', Icons.location_on_rounded, 'Live Location', AppColors.aqua),
    ('audio', Icons.hearing_rounded, 'Audio Detect', AppColors.neonPurple),
    ('circle', Icons.groups_rounded, 'Family Circle', AppColors.neonCyan),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (key, icon, label, tint) in _items) ...[
          Expanded(
            child: _ActionTile(
              icon: icon,
              label: label,
              tint: tint,
              onTap: () => onTap?.call(key),
            ),
          ),
          if (key != _items.last.$1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  /// Reserved for per-action theming; icons currently use the brand
  /// gradient so all four read as one set.
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.055),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          children: [
            GradientIcon(icon, size: 26),
            const SizedBox(height: 10),
            // Labels vary in length; scale rather than wrap or clip.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
