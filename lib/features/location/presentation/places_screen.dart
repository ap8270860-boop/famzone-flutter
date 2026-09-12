import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/place_models.dart';
import '../state/location_store.dart';
import 'widgets/map_style.dart';
import 'widgets/place_editor_sheet.dart';

/// The list of places, away from the map.
///
/// Everything here can also be done on the map, and on the map it is better —
/// you can see where the circle actually falls. This screen exists for the
/// two things the map is bad at: finding a place you set up months ago in a
/// city you are not currently in, and turning one person's notifications off
/// without hunting for their circle.
///
/// Sits on the app's own dark canvas rather than the map's daylight palette.
/// It is a settings screen that happens to be about places, and settings
/// screens in SFamily are navy.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  final LocationStore _store = LocationStore.instance;

  @override
  void initState() {
    super.initState();

    // The map may never have been opened this session, so the places list
    // cannot be assumed loaded.
    if (!_store.loaded) _store.bootstrap();
  }

  Future<void> _edit(FamilyPlace place) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceEditorSheet(
        place: place,
        palette: MapPalette.night,
        onSave: _store.savePlace,
        onDelete: place.id.isEmpty
            ? null
            : () => _confirmDelete(place),
      ),
    );
  }

  /// Deleting takes a confirmation, and the confirmation says what is lost.
  ///
  /// "Are you sure?" is a question nobody reads. Naming the place and saying
  /// the notifications stop is the difference between a dialog people dismiss
  /// and one they answer.
  Future<void> _confirmDelete(FamilyPlace place) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        title: Text(
          'Remove ${place.name}?',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
        ),
        content: const Text(
          'Arrival and departure alerts for this place stop, and it comes off '
          'the map. Nobody else is affected.',
          style: TextStyle(color: AppColors.textMuted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.alertRed,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok == true) await _store.deletePlace(place.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Family places'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          final places = _store.places;

          if (places.isEmpty) return const _Empty();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: places.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _PlaceRow(
              place: places[index],
              onTap: () => _edit(places[index]),
            ),
          );
        },
      ),
      /*
       | Back to the map, not "add place".
       |
       | A place needs a position and a position needs a map — see [_Empty].
       | This screen is reached from the map, so popping is literally the
       | shortest path to creating one, and a button that says where it goes
       | beats a button that opens a form asking for a latitude.
       */
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).maybePop(),
        backgroundColor: AppColors.canvasRaised,
        icon: const Icon(Icons.map_rounded, color: AppColors.mint),
        label: const Text(
          'Add from the map',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Why there is no "Add place" button here.
///
/// A place needs a position, and a position needs a map. A form with two
/// coordinate fields is not an alternative — nobody knows their own latitude.
/// So creation lives entirely on the map, where you put the circle where you
/// mean it, and this screen points at it rather than offering a worse path.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_location_alt_rounded,
              size: 42,
              color: AppColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            const Text(
              'No places yet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Open the family map and press and hold anywhere to add Home, '
              'School or anywhere else that matters. Your family will then '
              'show as "At Home" instead of a pair of coordinates.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.onTap});

  final FamilyPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = !place.notifyOnArrive && !place.notifyOnLeave;

    return Material(
      color: AppColors.glassFill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: place.tint.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(place.icon, size: 20, color: place.tint),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          place.radiusLabel,
                          style: TextStyle(
                            color: place.tint,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '  ·  ',
                          style: TextStyle(
                            color: AppColors.textMuted.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            muted ? 'Alerts off' : 'Alerts on',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textMuted.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
