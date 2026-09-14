import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/reminder_models.dart';
import '../state/reminder_store.dart';
import 'widgets/category_theme.dart';

/// Pick what kind of reminder this is, then which one.
///
/// Two steps in one sheet rather than two screens. The categories are a
/// twelve-tile grid you recognise by colour before you read; tapping one slides
/// its presets in underneath, and tapping a preset opens the editor already
/// filled in. The whole point is that setting "Wake Up at 6:30 on weekdays"
/// should be three taps and no typing.
///
/// Returns the chosen category and preset, or null if dismissed. The preset is
/// null for the Custom tile and for "something else" — both of which mean an
/// empty editor in that category.
class ReminderCatalogueSheet extends StatefulWidget {
  const ReminderCatalogueSheet({super.key});

  static Future<ReminderPick?> show(BuildContext context) {
    return showModalBottomSheet<ReminderPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ReminderCatalogueSheet(),
    );
  }

  @override
  State<ReminderCatalogueSheet> createState() => _ReminderCatalogueSheetState();
}

/// What the sheet hands back.
class ReminderPick {
  const ReminderPick({required this.category, this.template});

  final ReminderCategory category;
  final ReminderTemplate? template;
}

class _ReminderCatalogueSheetState extends State<ReminderCatalogueSheet> {
  final ReminderStore _store = ReminderStore.instance;

  ReminderCategory? _open;

  @override
  void initState() {
    super.initState();

    // Cheap after the first time: the catalogue is fetched once per session
    // and cached for an hour on the server.
    _store.loadCatalogue();
  }

  void _choose(ReminderCategory category) {
    /*
     | The Custom tile skips the second step entirely.
     |
     | It has no presets by design — the whole reason somebody taps it is that
     | nothing in the list fits — so showing them an empty shelf before the
     | editor would be a step that exists only to be dismissed.
     */
    if (category.isCustom || category.templates.isEmpty) {
      Navigator.of(context).pop(ReminderPick(category: category));

      return;
    }

    setState(() => _open = category);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
      decoration: const BoxDecoration(
        color: AppColors.canvasRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _header(),
          Flexible(
            child: AnimatedBuilder(
              animation: _store,
              builder: (context, _) => _body(media.viewPadding.bottom),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final open = _open;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 6),
      child: Row(
        children: [
          // Back, but only on the second step. A back arrow on the first step
          // would look like it closes the sheet, which it does not.
          if (open != null)
            IconButton(
              onPressed: () => setState(() => _open = null),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  open?.name ?? 'New reminder',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  open?.tagline ?? 'What is it for?',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(double inset) {
    final categories = _store.catalogue.categories;

    if (categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.mint),
        ),
      );
    }

    final open = _open;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: open == null
          ? _grid(categories, inset)
          : _templates(open, inset),
    );
  }

  /// Twelve tiles.
  ///
  /// Three across at 360dp gives each one 100dp — enough for a 28dp glyph and
  /// a word underneath at a readable size, and it puts all twelve on one
  /// screen with room to spare rather than making people scroll a menu they
  /// are trying to scan.
  Widget _grid(List<ReminderCategory> categories, double inset) {
    return GridView.builder(
      key: const ValueKey('grid'),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + inset),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.98,
      ),
      itemCount: categories.length,
      itemBuilder: (context, i) => _CategoryTile(
        category: categories[i],
        onTap: () => _choose(categories[i]),
      ),
    );
  }

  Widget _templates(ReminderCategory category, double inset) {
    final theme = CategoryTheme.of(
      category.colourFrom,
      category.colourTo,
      category.vibe,
    );

    return ListView(
      key: ValueKey('templates:${category.key}'),
      padding: EdgeInsets.fromLTRB(20, 6, 20, 20 + inset),
      shrinkWrap: true,
      children: [
        for (final template in category.templates)
          _TemplateRow(
            template: template,
            theme: theme,
            onTap: () => Navigator.of(context).pop(
              ReminderPick(category: category, template: template),
            ),
          ),

        const SizedBox(height: 6),

        // The escape hatch. Every category needs one: the presets are a
        // convenience, never the full set of things somebody might want to be
        // reminded of at breakfast time.
        _TemplateRow(
          template: null,
          theme: theme,
          label: 'Something else',
          onTap: () => Navigator.of(context).pop(
            ReminderPick(category: category),
          ),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final ReminderCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = CategoryTheme.of(
      category.colourFrom,
      category.colourTo,
      category.vibe,
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          /*
           | Static in the grid.
           |
           | Twelve simultaneous animations is twelve tickers repainting every
           | frame for decoration nobody is looking at yet — which shows up
           | immediately as jank on the mid-range Android this app mostly runs
           | on. The motion belongs on the editor header, where there is one
           | of it and the person has chosen to be there.
           */
          VibeBackdrop(theme: theme, animate: false),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CategoryTheme.icon(category.icon),
                  size: 26,
                  color: theme.onGradient,
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    category.name,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: theme.onGradient,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.template,
    required this.theme,
    required this.onTap,
    this.label,
  });

  final ReminderTemplate? template;
  final CategoryTheme theme;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = template;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    t == null
                        ? Icons.add_rounded
                        : CategoryTheme.icon(t.icon),
                    size: 19,
                    color: theme.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t?.name ?? label ?? 'Something else',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // The suggested time, so somebody can see at a glance that
                // tapping this is nearly finished rather than nearly started.
                if (t?.defaultTime != null)
                  Text(
                    t!.defaultTime!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: theme.accent,
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: AppColors.textMuted.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
