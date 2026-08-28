import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../people/data/people_models.dart';
import '../data/posts_api.dart';
import 'widgets/tag_picker_sheet.dart';

/// Pick a photo, crop it square, caption it, tag people, publish.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _api = PostsApi();
  final _picker = ImagePicker();
  final _caption = TextEditingController();

  File? _image;

  /// The file as it came out of the picker, kept so changing shape re-crops
  /// from the original rather than from an already-cropped JPEG. Cropping a
  /// crop loses a little quality every time, and it cannot recover pixels the
  /// previous crop threw away.
  String? _sourcePath;

  PostShape _shape = PostShape.portrait;
  List<PersonSummary> _tagged = const [];
  bool _posting = false;

  @override
  void dispose() {
    _caption.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Straight to the picker — this screen has nothing to show until a photo
    // is chosen, and an empty page with one button is a wasted tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickSource());
  }

  Future<void> _pickSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SourceSheet(),
    );

    if (source == null) {
      // Backed out without choosing, and there is nothing on screen yet.
      if (mounted && _image == null) Navigator.of(context).pop();
      return;
    }

    await _pick(source);
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        // Cap the source before cropping: a 12 MP phone photo is 4 MB of
        // upload for an image that will be displayed at 1080 square.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );

      if (picked == null || !mounted) return;

      _sourcePath = picked.path;

      await _crop();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not open that photo.');
    }
  }

  /// Crop the picked file to the selected shape.
  ///
  /// Split out from picking so switching shape re-runs only this half — the
  /// user does not have to find the photo again to change their mind.
  Future<void> _crop() async {
    final source = _sourcePath;

    if (source == null) return;

    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: source,
        aspectRatio: CropAspectRatio(
          ratioX: _shape.x,
          ratioY: _shape.y,
        ),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop photo',
            toolbarColor: AppColors.canvasRaised,
            toolbarWidgetColor: AppColors.textPrimary,
            statusBarColor: AppColors.canvas,
            backgroundColor: AppColors.canvas,
            activeControlsWidgetColor: AppColors.mint,
            dimmedLayerColor: Colors.black54,
            cropFrameColor: AppColors.mint,
            cropGridColor: Colors.white24,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: true,
          ),
          IOSUiSettings(
            title: 'Crop photo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
          ),
        ],
      );

      if (cropped == null || !mounted) return;

      setState(() => _image = File(cropped.path));
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not crop that photo.');
    }
  }

  Future<void> _setShape(PostShape shape) async {
    if (shape == _shape) return;

    setState(() => _shape = shape);

    // Re-crop immediately: a shape chip that only takes effect on the next
    // photo would be a setting, not a choice about this one.
    await _crop();
  }

  Future<void> _pickTags() async {
    final chosen = await showModalBottomSheet<List<PersonSummary>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => TagPickerSheet(selected: _tagged),
    );

    if (chosen != null && mounted) setState(() => _tagged = chosen);
  }

  Future<void> _share() async {
    if (_image == null || _posting) return;

    setState(() => _posting = true);

    try {
      final res = await _api.create(
        imagePath: _image!.path,
        caption: _caption.text.trim(),
        tagged: _tagged.map((p) => p.id).toList(),
      );

      if (!mounted) return;

      if (res.success) {
        AppToast.success(context, res.message);
        Navigator.of(context).pop(true);
      } else {
        AppToast.error(context, _firstError(res.errors) ?? res.message);
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String? _firstError(dynamic errors) {
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 20, 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'New post',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _image == null
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.mint),
                      )
                    : _form(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
      physics: const BouncingScrollPhysics(),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: _shape.ratio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(_image!, fit: BoxFit.cover),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: GestureDetector(
                    onTap: _pickSource,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded,
                              size: 15, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Change',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            for (final shape in PostShape.values) ...[
              Expanded(
                child: _ShapeChip(
                  shape: shape,
                  selected: shape == _shape,
                  onTap: () => _setShape(shape),
                ),
              ),
              if (shape != PostShape.values.last) const SizedBox(width: 9),
            ],
          ],
        ),
        const SizedBox(height: 16),

        GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          radius: 16,
          child: TextField(
            controller: _caption,
            maxLines: 5,
            minLines: 3,
            maxLength: 2200,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(
                fontSize: 14, height: 1.4, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              counterStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
              hintText: 'Write a caption…',
              hintStyle: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ),
        ),
        const SizedBox(height: 12),

        GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          radius: 16,
          onTap: _pickTags,
          child: Row(
            children: [
              const Icon(Icons.person_add_alt_1_outlined,
                  size: 19, color: AppColors.aqua),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _tagged.isEmpty
                      ? 'Tag people'
                      : _tagged.map((p) => p.handle).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: _tagged.isEmpty
                        ? FontWeight.w500
                        : FontWeight.w600,
                    color: _tagged.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
        const SizedBox(height: 22),

        PrimaryButton(
          label: 'Share',
          loading: _posting,
          onPressed: _share,
        ),
      ],
    );
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14, 12, 14, 14 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.canvasRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _row(context, Icons.photo_library_outlined, 'Choose from gallery',
              ImageSource.gallery),
          _row(context, Icons.photo_camera_outlined, 'Take a photo',
              ImageSource.camera),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label,
          ImageSource source) =>
      GestureDetector(
        onTap: () => Navigator.of(context).pop(source),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 15),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
}

/// The two shapes a post can take.
///
/// Portrait is the default because photos of people are mostly portrait, and
/// a square crop takes the top and bottom off them. Square stays available
/// because it suits scenery, food and anything symmetrical.
///
/// Deliberately two, not a free ratio: every post fits one of two boxes, so a
/// grid and a feed can be laid out without measuring each image first.
enum PostShape {
  portrait(4, 5, 'Portrait', Icons.crop_portrait_rounded),
  square(1, 1, 'Square', Icons.crop_square_rounded);

  const PostShape(this.x, this.y, this.label, this.icon);

  /// Doubles, because CropAspectRatio takes doubles. The enum values below
  /// still read as `4, 5` — Dart promotes an int literal to double when the
  /// context asks for one, so only the field types change.
  final double x;
  final double y;

  final String label;
  final IconData icon;

  double get ratio => x / y;
}

class _ShapeChip extends StatelessWidget {
  const _ShapeChip({
    required this.shape,
    required this.selected,
    required this.onTap,
  });

  final PostShape shape;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? AppColors.mint.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected
                ? AppColors.mint.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              shape.icon,
              size: 17,
              color: selected ? AppColors.mint : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              shape.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.mint : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
