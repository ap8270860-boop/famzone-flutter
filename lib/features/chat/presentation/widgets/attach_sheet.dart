import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// What the + button offers.
enum AttachChoice { camera, gallery, document, location }

/// The attachment sheet.
///
/// A sheet of choices rather than the + button dropping straight into the
/// gallery: "attach" is three different intentions — take one now, pick one
/// you have, send a file — and guessing which costs a wrong screen and a
/// trip back.
///
/// Tiles rather than a list, because these are picked by shape and colour
/// after the first couple of times, not by reading.
Future<AttachChoice?> showAttachSheet(BuildContext context) {
  return showModalBottomSheet<AttachChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AttachSheet(),
  );
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(
        12, 0, 12, 12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.canvasRaised,
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Tile(
                icon: Icons.photo_camera_rounded,
                label: 'Camera',
                tint: AppColors.aqua,
                onTap: () => Navigator.of(context).pop(AttachChoice.camera),
              ),
              _Tile(
                icon: Icons.photo_library_rounded,
                label: 'Photos',
                tint: AppColors.mint,
                onTap: () => Navigator.of(context).pop(AttachChoice.gallery),
              ),
              _Tile(
                icon: Icons.insert_drive_file_rounded,
                label: 'Document',
                tint: AppColors.neonPurple,
                onTap: () => Navigator.of(context).pop(AttachChoice.document),
              ),
              _Tile(
                icon: Icons.near_me_rounded,
                label: 'Location',
                tint: AppColors.warmGold,
                onTap: () => Navigator.of(context).pop(AttachChoice.location),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        // Four across has to fit a 320 dp screen without overflowing.
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // A tinted disc rather than a flat fill: the colour is the
                // thing being recognised, and a solid circle at this size
                // shouts louder than the conversation behind it.
                color: tint.withValues(alpha: 0.16),
                border: Border.all(color: tint.withValues(alpha: 0.45)),
              ),
              child: Icon(icon, size: 25, color: tint),
            ),
            const SizedBox(height: 9),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
