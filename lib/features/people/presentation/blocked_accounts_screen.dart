import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../data/people_api.dart';
import '../data/people_models.dart';
import 'widgets/person_avatar.dart';

/// Everyone this user has blocked.
///
/// This screen is not optional decoration. A blocked account is hidden from
/// search and its profile is unreachable, so without a list here a block would
/// be permanent by accident — there would be no route back to the Unblock
/// button.
class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  final _api = PeopleApi();

  List<PersonSummary> _blocked = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.blockedAccounts();

      if (!mounted) return;

      setState(() {
        if (res.success) {
          _blocked = (res.dataMap['blocked'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map(PersonSummary.fromJson)
                  .toList() ??
              const [];
          _error = null;
        } else {
          _error = res.message;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server.';
        _loading = false;
      });
    }
  }

  Future<void> _unblock(PersonSummary person) async {
    if (_busy.contains(person.id)) return;

    setState(() => _busy.add(person.id));

    try {
      final res = await _api.unblock(person.id);

      if (!mounted) return;

      if (res.success) {
        // Drop the row immediately — the list is defined by the blocks, and
        // reloading just to remove one entry is a round trip for nothing.
        setState(() => _blocked.removeWhere((p) => p.id == person.id));
        AppToast.success(context, res.message);
      } else {
        AppToast.error(context, res.message);
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy.remove(person.id));
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
                        'Blocked accounts',
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
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }

    if (_error != null) {
      return _message(
        Icons.cloud_off_rounded,
        'Something went wrong',
        _error!,
      );
    }

    if (_blocked.isEmpty) {
      return _message(
        Icons.verified_user_outlined,
        'Nobody is blocked',
        'People you block will appear here, and this is where you unblock '
            'them.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.mint,
      backgroundColor: AppColors.canvasRaised,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: _blocked.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final person = _blocked[i];

          return GlassCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            radius: 16,
            child: Row(
              children: [
                PersonAvatar(
                  size: 46,
                  imageUrl: person.avatarUrl,
                  initials: person.initials,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        person.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _unblock(person),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 34,
                    constraints: const BoxConstraints(minWidth: 92),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white.withValues(alpha: 0.07),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: _busy.contains(person.id)
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textPrimary,
                            ),
                          )
                        : const Text(
                            'Unblock',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _message(IconData icon, String title, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 0, 44, 70),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 46, color: AppColors.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
