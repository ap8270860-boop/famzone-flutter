import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../location/presentation/widgets/map_style.dart';
import '../../location/state/location_permissions.dart';
import '../../location/state/location_tracker.dart';
import '../data/sos_api.dart';
import '../data/sos_models.dart';
import 'widgets/service_glyph.dart';

/// One kind of help, in full.
///
/// The order of this screen is the order somebody needs it in, and it is not
/// the order that looks best:
///
///  1. The warning, if getting this wrong is dangerous. Before anything.
///  2. The number. Big, and reachable with one thumb without scrolling.
///  3. What to do while you wait.
///  4. Where to go, if going somewhere is useful.
///
/// Nearby places are last on purpose. They are the part that can fail — they
/// need a location fix, a network, and a Google quota — and putting anything
/// that fragile above a phone number would mean a spinner sitting where 112
/// should be.
class SosServiceScreen extends StatefulWidget {
  const SosServiceScreen({super.key, required this.service});

  final EmergencyService service;

  @override
  State<SosServiceScreen> createState() => _SosServiceScreenState();
}

class _SosServiceScreenState extends State<SosServiceScreen> {
  final SosApi _api = SosApi();
  final TextEditingController _search = TextEditingController();

  List<NearbyPlace> _places = const [];
  bool _searching = false;
  bool _mapView = false;
  String? _placesError;

  /// Whether nearby search can work at all on this server.
  ///
  /// Kept so the search box can be disabled rather than left there inviting
  /// somebody to type into something that cannot answer.
  bool _searchAvailable = true;

  double? _lat;
  double? _lng;

  GoogleMapController? _map;
  Timer? _debounce;

  EmergencyService get _service => widget.service;

  @override
  void initState() {
    super.initState();

    if (_service.canSearch) _locateAndSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _map?.dispose();

    super.dispose();
  }

  /*
  |----------------------------------------------------------------------------
  | Finding places
  |----------------------------------------------------------------------------
  */

  Future<void> _locateAndSearch() async {
    final known = LocationTracker.instance.myPosition;

    var lat = known?.latitude;
    var lng = known?.longitude;

    if (lat == null || lng == null) {
      final access = await LocationPermissions.check();

      if (!access.canTrack) {
        if (!mounted) return;

        setState(() => _placesError = 'Location is off, so we cannot find '
            'places near you. The numbers above still work.');

        return;
      }

      final fix = await LocationTracker.instance.currentFix();

      lat = fix?.latitude;
      lng = fix?.longitude;
    }

    if (lat == null || lng == null) {
      if (!mounted) return;

      setState(() => _placesError = 'Waiting for a location fix.');

      return;
    }

    _lat = lat;
    _lng = lng;

    await _fetch();
  }

  Future<void> _fetch({String? query}) async {
    final lat = _lat;
    final lng = _lng;

    if (lat == null || lng == null) return;

    setState(() {
      _searching = true;
      _placesError = null;
    });

    try {
      final response = await _api.nearby(
        latitude: lat,
        longitude: lng,
        category: (query == null || query.isEmpty) ? _service.key : null,
        query: query,
      );

      if (!mounted) return;

      if (!response.success) {
        setState(() => _placesError = response.message);

        return;
      }

      final data = response.dataMap;

      final places = ((data['places'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(NearbyPlace.fromJson)
          .toList();

      setState(() {
        _places = places;

        /*
         | The server's own words, when it has any.
         |
         | An empty list has four completely different causes — the key is
         | not configured, Google refused it, the quota is gone, or there
         | genuinely is no hospital within five kilometres — and they have
         | four different fixes. Showing "Nothing found nearby" for all of
         | them is how somebody spends an afternoon looking in the wrong
         | place, which is exactly what happened.
         */
        _placesError = places.isEmpty
            ? (data['reason'] as String? ?? 'Nothing found within 5 km.')
            : null;

        _searchAvailable = data['available'] as bool? ?? true;
      });

      _fitMap();
    } catch (_) {
      if (mounted) {
        setState(() => _placesError = 'Could not search right now.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Typed search, debounced.
  ///
  /// Every keystroke here is a billed Google call if it reaches the server, so
  /// the debounce is not a nicety — it is the difference between one lookup
  /// and one per letter.
  void _onQueryChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;

      _fetch(query: value.trim().isEmpty ? null : value.trim());
    });
  }

  void _fitMap() {
    final points = _places.where((p) => p.hasPoint).toList();

    if (points.isEmpty || _map == null) return;

    if (points.length == 1) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(points.first.latitude!, points.first.longitude!),
        15,
      ));

      return;
    }

    var minLat = points.first.latitude!;
    var maxLat = minLat;
    var minLng = points.first.longitude!;
    var maxLng = minLng;

    for (final p in points) {
      minLat = p.latitude! < minLat ? p.latitude! : minLat;
      maxLat = p.latitude! > maxLat ? p.latitude! : maxLat;
      minLng = p.longitude! < minLng ? p.longitude! : minLng;
      maxLng = p.longitude! > maxLng ? p.longitude! : maxLng;
    }

    _map!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      56,
    ));
  }

  /*
  |----------------------------------------------------------------------------
  | Calling
  |----------------------------------------------------------------------------
  */

  /// Open the dialler with the number already in it.
  ///
  /// `tel:` deliberately does not dial by itself — the person still taps the
  /// green button. An app that placed the call outright would place one every
  /// time somebody brushed the screen, and the whole point of this screen is
  /// that its buttons are safe to touch.
  Future<void> _dial(String number) async {
    if (number.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: number);

    try {
      final opened = await launchUrl(uri);

      if (!opened && mounted) {
        AppToast.show(
          context,
          'Could not open the dialler. The number is $number.',
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          'Could not open the dialler. The number is $number.',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _openPlace(NearbyPlace place) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PlaceSheet(
        place: place,
        tint: _service.tint,
        api: _api,
        onDial: _dial,
      ),
    );
  }

  Future<void> _openLink(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not open that link.',
            type: ToastType.error);
      }
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Build
  |----------------------------------------------------------------------------
  */

  @override
  Widget build(BuildContext context) {
    final primary = _service.primaryNumber;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 2),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.textPrimary,
                  ),
                  Expanded(
                    child: Text(
                      _service.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16, 6, 16, 28 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Center(
                    child: ServiceGlyph(
                      icon: _service.icon,
                      tint: _service.tint,
                      size: 122,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _service.tagline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Before the number, not after it. A warning that arrives
                  // once you have already acted is not a warning.
                  if (_service.warning != null) ...[
                    _WarningBar(text: _service.warning!),
                    const SizedBox(height: 16),
                  ],

                  if (primary != null)
                    _CallButton(
                      number: primary,
                      tint: _service.tint,
                      onTap: () => _dial(primary.dialable),
                    ),

                  if (_service.alternates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ..._service.alternates.map(
                      (number) => _AlternateRow(
                        number: number,
                        onTap: () => _dial(number.dialable),
                      ),
                    ),
                  ],

                  if (_service.linkUrl != null) ...[
                    const SizedBox(height: 6),
                    _LinkRow(
                      label: _service.linkLabel ?? 'Open',
                      onTap: () => _openLink(_service.linkUrl!),
                    ),
                  ],

                  if (_service.guidance.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    const _SectionTitle('While help is on the way'),
                    const SizedBox(height: 12),
                    ..._service.guidance.asMap().entries.map(
                          (e) => _GuidanceLine(
                            index: e.key + 1,
                            text: e.value,
                            tint: _service.tint,
                          ),
                        ),
                  ],

                  if (_service.canSearch) ...[
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        Expanded(
                          child: _SectionTitle(
                            _service.searchLabel ?? 'Nearby',
                          ),
                        ),
                        _ViewToggle(
                          mapView: _mapView,
                          onChanged: (value) {
                            setState(() => _mapView = value);

                            if (value) {
                              // The controller only exists once the map has
                              // been built at least once.
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) => _fitMap());
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SearchField(
                      controller: _search,
                      busy: _searching,
                      enabled: _searchAvailable,
                      onChanged: _onQueryChanged,
                    ),
                    const SizedBox(height: 12),
                    if (_mapView)
                      _PlacesMap(
                        places: _places,
                        tint: _service.tint,
                        lat: _lat,
                        lng: _lng,
                        onCreated: (controller) {
                          _map = controller;
                          _fitMap();
                        },
                        onTapPlace: _openPlace,
                      )
                    else
                      _PlacesList(
                        places: _places,
                        searching: _searching,
                        error: _placesError,
                        tint: _service.tint,
                        onTap: _openPlace,
                      ),
                  ],

                  if (_service.disclaimer != null) ...[
                    const SizedBox(height: 22),
                    _Note(text: _service.disclaimer!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
|------------------------------------------------------------------------------
| Pieces
|------------------------------------------------------------------------------
*/

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _WarningBar extends StatelessWidget {
  const _WarningBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: AppColors.alertRed.withValues(alpha: 0.13),
        border: Border.all(color: AppColors.alertRed.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.alertRed,
            size: 20,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.number,
    required this.tint,
    required this.onTap,
  });

  final EmergencyNumber number;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                tint.withValues(alpha: 0.30),
                tint.withValues(alpha: 0.16),
              ],
            ),
            border: Border.all(color: tint.withValues(alpha: 0.70), width: 1.4),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint.withValues(alpha: 0.22),
                ),
                child: Icon(Icons.call_rounded, color: tint, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Call ${number.number}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      number.label,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: tint, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlternateRow extends StatelessWidget {
  const _AlternateRow({required this.number, required this.onTap});

  final EmergencyNumber number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.phone_outlined,
                  size: 17,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 12),
                Text(
                  number.number,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    number.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: AppColors.neonCyan),
      icon: const Icon(Icons.open_in_new_rounded, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13.5)),
    );
  }
}

class _GuidanceLine extends StatelessWidget {
  const _GuidanceLine({
    required this.index,
    required this.text,
    required this.tint,
  });

  final int index;
  final String text;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.18),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: tint,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.mapView, required this.onChanged});

  final bool mapView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.format_list_bulleted_rounded,
            selected: !mapView,
            onTap: () => onChanged(false),
          ),
          _Segment(
            icon: Icons.map_outlined,
            selected: mapView,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.electricBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          icon,
          size: 17,
          color: selected ? Colors.white : AppColors.textMuted,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.busy,
    required this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: enabled
            ? 'Search by name or area'
            : 'Search is not available',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textMuted,
          size: 20,
        ),
        suffixIcon: busy
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.neonCyan,
                  ),
                ),
              )
            : null,
        filled: true,
        fillColor: AppColors.glassFill,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.neonCyan),
        ),
      ),
    );
  }
}

class _PlacesList extends StatelessWidget {
  const _PlacesList({
    required this.places,
    required this.searching,
    required this.error,
    required this.tint,
    required this.onTap,
  });

  final List<NearbyPlace> places;
  final bool searching;
  final String? error;
  final Color tint;
  final ValueChanged<NearbyPlace> onTap;

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.glassFill,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Center(
          child: searching
              ? const CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.neonCyan,
                )
              : Text(
                  error ?? 'Nothing found nearby.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
        ),
      );
    }

    return Column(
      children: [
        for (final place in places)
          _PlaceRow(place: place, tint: tint, onTap: () => onTap(place)),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.tint,
    required this.onTap,
  });

  final NearbyPlace place;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.place_rounded, size: 19, color: tint),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              place.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!place.operational) ...[
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.alertRed
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'CLOSED',
                                style: TextStyle(
                                  color: AppColors.alertRed,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        place.address ?? place.kind ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (place.distanceLabel != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    place.distanceLabel!,
                    style: TextStyle(
                      color: tint,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlacesMap extends StatelessWidget {
  const _PlacesMap({
    required this.places,
    required this.tint,
    required this.lat,
    required this.lng,
    required this.onCreated,
    required this.onTapPlace,
  });

  final List<NearbyPlace> places;
  final Color tint;
  final double? lat;
  final double? lng;
  final ValueChanged<GoogleMapController> onCreated;
  final ValueChanged<NearbyPlace> onTapPlace;

  @override
  Widget build(BuildContext context) {
    final hue = HSVColor.fromColor(tint).hue;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 340,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(lat ?? 20.5937, lng ?? 78.9629),
            zoom: lat == null ? 4 : 13,
          ),

          // The loud variant: hospitals and police stations keep their icons
          // here, because on this screen the map *is* the answer rather than
          // the backdrop to it.
          style: MapStyle.emergency,

          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          onMapCreated: onCreated,

          markers: {
            for (final place in places)
              if (place.hasPoint)
                Marker(
                  markerId: MarkerId(place.placeId),
                  position: LatLng(place.latitude!, place.longitude!),
                  icon: BitmapDescriptor.defaultMarkerWithHue(hue),
                  infoWindow: InfoWindow(
                    title: place.name,
                    snippet: place.distanceLabel,
                    onTap: () => onTapPlace(place),
                  ),
                  onTap: () => onTapPlace(place),
                ),
          },
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/*
|------------------------------------------------------------------------------
| One place
|------------------------------------------------------------------------------
*/

/// Tapping a hospital.
///
/// The phone number is fetched *here*, when the sheet opens, and nowhere
/// else. Google bills contact details at its scarcest tier, so a list of
/// twenty places must never carry twenty numbers — that would be twenty
/// Enterprise calls to answer a question nobody asked. One tap, one lookup.
class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet({
    required this.place,
    required this.tint,
    required this.api,
    required this.onDial,
  });

  final NearbyPlace place;
  final Color tint;
  final SosApi api;
  final Future<void> Function(String number) onDial;

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  PlaceContact? _contact;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final response = await widget.api.contact(widget.place.placeId);

      if (!mounted) return;

      if (response.success) {
        setState(() => _contact = PlaceContact.fromJson(response.dataMap));
      }
    } catch (_) {
      // Falls through to "no number listed", which is the honest answer —
      // plenty of places genuinely have none on file.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _directions() async {
    final lat = widget.place.latitude ?? _contact?.latitude;
    final lng = widget.place.longitude ?? _contact?.longitude;

    /*
     | Handed off to the phone's own maps app.
     |
     | Costs no Google quota at all, and gives the person turn-by-turn
     | directions, traffic and transit — everything a real maps app does that
     | ours never will. In an emergency that handoff is the most useful thing
     | this sheet can do.
     */
    final uri = _contact?.mapsUrl != null
        ? Uri.parse(_contact!.mapsUrl!)
        : Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
          );

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not open maps.', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final phone = _contact?.dialable ?? '';

    return Container(
      margin: EdgeInsets.fromLTRB(
        12, 0, 12, 12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.canvasRaised,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
          ),
          Text(
            place.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (place.address != null) ...[
            const SizedBox(height: 6),
            Text(
              place.address!,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          if (place.distanceLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.near_me_rounded, size: 14, color: widget.tint),
                const SizedBox(width: 7),
                Text(
                  '${place.distanceLabel} away',
                  style: TextStyle(
                    color: widget.tint,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _loading || phone.isEmpty
                        ? null
                        : () => widget.onDial(phone),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.tint.withValues(alpha: 0.24),
                      foregroundColor: widget.tint,
                      disabledBackgroundColor: AppColors.glassFill,
                      disabledForegroundColor: AppColors.textMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: _loading
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textMuted,
                            ),
                          )
                        : const Icon(Icons.call_rounded, size: 19),
                    label: Text(
                      _loading
                          ? 'Getting number'
                          : (phone.isEmpty ? 'No number listed' : 'Call'),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _directions,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.glassBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.directions_rounded, size: 19),
                    label: const Text(
                      'Directions',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!_loading && phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                _contact?.phone ?? _contact?.phoneInternational ?? '',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
