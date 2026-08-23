import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';

/// Circular avatar with a camera badge, and a sheet offering camera, gallery
/// or removal.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    super.key,
    required this.onPicked,
    required this.onRemoved,
    this.imageUrl,
    this.localFile,
    this.initials = '?',
    this.size = 104,
    this.busy = false,
    this.label,
    this.accent = AppColors.aqua,
  });

  final ValueChanged<XFile> onPicked;
  final VoidCallback onRemoved;
  final String? imageUrl;
  final File? localFile;
  final String initials;
  final double size;
  final bool busy;
  final String? label;
  final Color accent;

  bool get _hasImage => localFile != null || imageUrl != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: busy ? null : () => _openSheet(context),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [accent, AppColors.mint],
                    ),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.canvasRaised,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: busy
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: AppColors.mint,
                              ),
                            ),
                          )
                        : _image(),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.safeGradient,
                      border: Border.all(color: AppColors.canvas, width: 2.5),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        size: 15, color: Color(0xFF04121F)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 9),
          Text(
            label!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _image() {
    if (localFile != null) {
      return Image.file(localFile!, fit: BoxFit.cover, width: size, height: size);
    }
    if (imageUrl != null) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => _initials(),
      );
    }
    return _initials();
  }

  Widget _initials() => Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.32,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      );

  Future<void> _openSheet(BuildContext context) async {
    final picker = ImagePicker();

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SourceSheet(canRemove: _hasImage),
    );

    if (choice == null) return;

    if (choice == 'remove') {
      onRemoved();
      return;
    }

    try {
      final file = await picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        // Resize on device. Uploading a 12 MP original to show a 104px circle
        // wastes the user's data and the server's disk.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file != null) onPicked(file);
    } catch (_) {
      // Permission refused, or no camera. Nothing to do but leave it be.
    }
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.canRemove});

  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.canvasRaised,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _tile(context, Icons.photo_camera_rounded, 'Take a photo', 'camera'),
            _tile(context, Icons.photo_library_rounded, 'Choose from gallery',
                'gallery'),
            if (canRemove)
              _tile(context, Icons.delete_outline_rounded, 'Remove photo',
                  'remove',
                  danger: true),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    bool danger = false,
  }) {
    final colour = danger ? AppColors.alertRed : AppColors.textPrimary;

    return ListTile(
      onTap: () => Navigator.of(context).pop(value),
      leading: Icon(icon, size: 21, color: colour),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: colour,
        ),
      ),
    );
  }
}
