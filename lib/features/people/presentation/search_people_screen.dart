import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../data/people_api.dart';
import '../data/people_models.dart';
import 'user_profile_screen.dart';
import 'widgets/person_row.dart';

/// Find people by name, username or phone.
class SearchPeopleScreen extends StatefulWidget {
  const SearchPeopleScreen({super.key});

  @override
  State<SearchPeopleScreen> createState() => _SearchPeopleScreenState();
}

class _SearchPeopleScreenState extends State<SearchPeopleScreen> {
  final _api = PeopleApi();
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;

  /// Rising counter so a slow response for an earlier query cannot overwrite
  /// the results of a later one. Without this, typing "fai" then "faisal" can
  /// leave you looking at the results for "fai" — the classic search race.
  int _requestId = 0;

  List<PersonSummary> _results = const [];
  bool _searching = false;
  bool _tooShort = false;
  String? _error;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    // Open with the keyboard up — this screen exists to be typed into.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _api.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();

    final term = value.trim();

    if (term.length < 2) {
      setState(() {
        _results = const [];
        _tooShort = term.isNotEmpty;
        _searching = false;
        _error = null;
      });
      return;
    }

    // 320ms: long enough that a normal typing burst is one request, short
    // enough that results feel like they arrive as you type.
    _debounce = Timer(const Duration(milliseconds: 320), () => _run(term));
  }

  Future<void> _run(String term) async {
    final id = ++_requestId;

    setState(() {
      _searching = true;
      _tooShort = false;
      _error = null;
      _lastQuery = term;
    });

    try {
      final res = await _api.search(term);

      if (!mounted || id != _requestId) return;

      if (res.success) {
        setState(() {
          _results = (res.dataMap['results'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map(PersonSummary.fromJson)
                  .toList() ??
              const [];
          _searching = false;
        });
      } else {
        setState(() {
          _error = res.message;
          _searching = false;
        });
      }
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = 'Could not reach the server.';
        _searching = false;
      });
    }
  }

  Future<void> _open(PersonSummary person) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: person.id)),
    );

    // The profile screen may have changed the relationship, so the row's
    // button would otherwise be stale when we come back.
    if (mounted && _lastQuery.isNotEmpty) _run(_lastQuery);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              _SearchBar(
                controller: _controller,
                focus: _focus,
                onChanged: _onChanged,
                onClear: () {
                  _controller.clear();
                  _onChanged('');
                },
                busy: _searching,
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        detail: _error!,
      );
    }

    if (_tooShort) {
      return const _Empty(
        icon: Icons.keyboard_rounded,
        title: 'Keep typing',
        detail: 'Enter at least two characters to search.',
      );
    }

    if (_controller.text.trim().isEmpty) {
      return const _Empty(
        icon: Icons.person_search_rounded,
        title: 'Find people',
        detail:
            'Search by name or username. To find someone by phone, type the '
            'full number.',
      );
    }

    if (_searching && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }

    if (_results.isEmpty) {
      return _Empty(
        icon: Icons.search_off_rounded,
        title: 'No one found',
        detail: 'Nobody matches "$_lastQuery". Check the spelling, or try '
            'their full phone number.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      physics: const BouncingScrollPhysics(),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final person = _results[i];

        return PersonRow(
          person: person,
          onTap: () => _open(person),
          onChanged: (updated) => setState(() => _results[i] = updated),
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onClear,
    required this.busy,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 16, 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.textMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      onChanged: onChanged,
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Name, username or phone',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mint,
                      ),
                    )
                  else if (controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: onClear,
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(42, 0, 42, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.textMuted.withValues(alpha: 0.5)),
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
