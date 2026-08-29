import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Open a photo full screen.
///
/// A route rather than a dialog, so the system back gesture closes it and it
/// gets its own entry in the stack — a full-screen image that swallows back
/// is the fastest way to make an app feel trapped.
Future<void> openImageViewer(
  BuildContext context, {
  String? url,
  String? localPath,
  String? caption,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, animation, __) => FadeTransition(
        opacity: animation,
        child: ImageViewer(url: url, localPath: localPath, caption: caption),
      ),
    ),
  );
}

class ImageViewer extends StatelessWidget {
  const ImageViewer({super.key, this.url, this.localPath, this.caption});

  final String? url;
  final String? localPath;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final path = localPath;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Tapping the backdrop closes. Expected of a full-screen photo, and
          // it means the close button is a convenience rather than the only
          // way out.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: path != null && File(path).existsSync()
                      ? Image.file(File(path))
                      : url == null
                          ? const Icon(Icons.broken_image_outlined,
                              size: 44, color: AppColors.textMuted)
                          : Image.network(
                              url!,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                      ? child
                                      : const SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor: AlwaysStoppedAnimation(
                                              Colors.white,
                                            ),
                                          ),
                                        ),
                              errorBuilder: (context, _, __) => const Icon(
                                Icons.broken_image_outlined,
                                size: 44,
                                color: AppColors.textMuted,
                              ),
                            ),
                ),
              ),
            ),
          ),

          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 6,
            left: 6,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          if (caption != null && caption!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 20 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                // A gradient rather than a solid bar: the caption stays
                // readable over a bright photo without boxing off the bottom
                // of the image.
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Text(
                  caption!,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
