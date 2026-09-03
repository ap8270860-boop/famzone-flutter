import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_api.dart';
import '../data/chat_models.dart';
import '../state/chat_store.dart';
import 'chat_screen.dart';

/// Name it, give it a picture, create it.
///
/// The second half of making a group. Everything arrives at the server in one
/// request — a two-step create would leave a group with no photo every time
/// the second call failed, and there is no good moment to retry that.
class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({
    super.key,
    required this.members,
    required this.scope,
  });

  final List<ChatPerson> members;
  final String scope;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final ChatApi _api = ChatApi();
  final TextEditingController _title = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _avatarPath;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _api.dispose();
    super.dispose();
  }

  bool get _canCreate => _title.text.trim().isNotEmpty && !_creating;

  Future<void> _pickPhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        // A group picture is drawn at 46px in a list. Anything past 1024
        // is bytes nobody will ever see.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (file == null || !mounted) return;

      setState(() => _avatarPath = file.path);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not open your photos.');
    }
  }

  Future<void> _create() async {
    if (!_canCreate) return;

    setState(() => _creating = true);

    try {
      final res = await _api.createGroup(
        title: _title.text.trim(),
        memberIds: widget.members.map((m) => m.id).toList(),
        scope: widget.scope,
        avatarPath: _avatarPath,
      );

      if (!mounted) return;

      if (!res.success) {
        setState(() => _creating = false);
        AppToast.error(context, res.message);

        return;
      }

      final conversation = Conversation.fromJson(
        res.dataMap,
        Session.instance.user?.id ?? '',
      );

      // The inbox has a thread it does not know about yet.
      ChatStore.instance.refresh();

      /*
       | Straight into the group, and the two creation screens are gone.
       |
       | popUntil first so Back from the group lands on the inbox rather than
       | walking back through the picker, which would offer to make the same
       | group a second time.
       */
      final navigator = Navigator.of(context);

      navigator.popUntil((route) => route.isFirst);

      await navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversation.id,
            // A group has no single person behind it; the header reads the
            // conversation itself.
            userId: '',
            name: conversation.displayName,
            avatarUrl: conversation.displayAvatarUrl,
            initials: conversation.displayInitials,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() => _creating = false);
      AppToast.error(context, 'Could not reach the server.');
    }
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
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'New group',
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _PhotoWell(path: _avatarPath, onTap: _pickPhoto),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _title,
                            autofocus: true,
                            maxLength: 80,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Group name',
                              counterText: '',
                              hintStyle: const TextStyle(
                                fontSize: 16,
                                color: AppColors.textMuted,
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: AppColors.mint),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 26),
                    Text(
                      widget.members.length == 1
                          ? '1 person'
                          : '${widget.members.length} people',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.14,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Named, not counted. This is the last screen before the
                    // group exists, and it is the only place to notice that
                    // one tap in the picker went astray.
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        for (final member in widget.members)
                          Container(
                            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.white.withValues(alpha: 0.06),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.09),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PersonAvatar(
                                  size: 24,
                                  imageUrl: member.avatarUrl,
                                  initials: member.initials,
                                  fontSize: 9,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  member.name,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              Container(
                padding: EdgeInsets.fromLTRB(
                  18, 12, 18, 14 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                ),
                child: GestureDetector(
                  onTap: _create,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: _canCreate ? AppColors.safeGradient : null,
                      color: _canCreate
                          ? null
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                    child: _creating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Color(0xFF04121F)),
                            ),
                          )
                        : Text(
                            _canCreate ? 'Create group' : 'Name the group',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: _canCreate
                                  ? const Color(0xFF04121F)
                                  : AppColors.textMuted.withValues(alpha: 0.8),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoWell extends StatelessWidget {
  const _PhotoWell({required this.path, required this.onTap});

  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          image: path == null
              ? null
              : DecorationImage(
                  image: FileImage(File(path!)),
                  fit: BoxFit.cover,
                ),
        ),
        child: path != null
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_camera_outlined,
                      size: 20, color: AppColors.textMuted.withValues(alpha: 0.9)),
                  const SizedBox(height: 3),
                  const Text(
                    'Photo',
                    style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                  ),
                ],
              ),
      ),
    );
  }
}
