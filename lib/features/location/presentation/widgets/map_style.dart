import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The map, dressed in the app's colours.
///
/// Google's default map is a bright, high-contrast document designed to be
/// read on its own. Dropped into a deep-navy app it reads as a hole punched
/// in the screen — and worse, it competes with the markers, which are the
/// only part anybody is actually looking at.
///
/// Three styles, because three screens want different things from one map:
///
///  - [light] is the family map by day, and the default. Close to the map
///    everybody already knows from Uber and Zomato, because familiarity is
///    the whole point: a driver, a street and a junction should read exactly
///    the way they read in the app somebody used an hour ago.
///  - [dark] is the same map at night, and carries the same landmarks. What
///    changes is the light, not the content — losing the mall and the metro
///    station after sunset would make the map useless at exactly the hour
///    somebody is most likely to be worried about where a person is.
///  - [emergency] is the SOS map. Loud where it matters: hospitals, police
///    stations and pharmacies are drawn with their icons, because there the
///    map *is* the answer rather than the backdrop to it.
class MapStyle {
  const MapStyle._();

  /*
  |----------------------------------------------------------------------------
  | Labels
  |----------------------------------------------------------------------------
  |
  | The first version of this style was too quiet. Turning `labels.icon` off
  | globally and dimming every label to #8a97b1 produced a handsome map that
  | could not answer "which area is that". Google's own map earns its
  | readability by making *place names* the brightest thing after the roads,
  | and dropping them in progressively as you zoom — city, then locality,
  | then neighbourhood, then street.
  |
  | So labels are tiered by importance rather than uniformly dimmed:
  | localities brightest, neighbourhoods next, streets quietest.
  |
  | Icons were off here too, on the same mistaken reasoning as the daylight
  | style — see the note above it. They are on now, desaturated rather than
  | deleted, because a landmark is how a person works out *where in the
  | neighbourhood* somebody is standing.
  |
  */

  /// Locality names — the brightest text on the map.
  static const String _locality = '#c3cfe6';

  /// Neighbourhoods and sub-localities, one step down.
  static const String _neighbourhood = '#9db0d0';

  /// Street names, quietest of the three.
  static const String _street = '#7e8dab';

  /// The halo behind every label, so text stays legible over roads and parks.
  static const String _halo = '#050d1c';

  /*
  |----------------------------------------------------------------------------
  | The daylight map
  |----------------------------------------------------------------------------
  |
  | The temptation with a branded app is to theme the daylight map — tint the
  | roads, wash the land in the app's navy, make it *ours*. That is the wrong
  | instinct here. A family map is read under stress, often by somebody who is
  | not technical, sometimes by a parent who has opened it because they are
  | worried, and the most legible map is the one whose conventions are already
  | in the reader's head from every ride-hailing and delivery app they use.
  |
  | ## What changed, and why the first version was wrong
  |
  | It turned business POIs off entirely, on the reasoning that they are
  | advertising and every one of them competes with a face. That reasoning is
  | half right and the conclusion was wrong.
  |
  | A map with only locality names is not a quiet map, it is a *featureless*
  | one. "Sector 62" tells you nothing about where in Sector 62 somebody is
  | standing. The landmarks are how a person actually navigates — near the
  | mall, opposite the hospital, by the metro station — and stripping them out
  | removed the thing that turns a dot into a place.
  |
  | So the POIs are back, and the competition with the markers is handled the
  | way it should have been in the first place: by *weight* rather than by
  | deletion. Place labels sit a shade lighter than road names, icons are
  | slightly desaturated so no single shopfront shouts, and the family markers
  | stay the only fully saturated thing on screen. Google already fades POIs
  | in progressively as you zoom, so the density looks after itself — sparse
  | across a city, detailed down a street.
  */
  static const String light = '''
[
  {"elementType":"geometry","stylers":[{"color":"#f4f6f8"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#4a5261"}]},
  {"elementType":"labels.text.stroke",
   "stylers":[{"color":"#ffffff"},{"weight":2.5}]},

  {"featureType":"administrative","elementType":"geometry.stroke",
   "stylers":[{"color":"#d5dae1"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill",
   "stylers":[{"color":"#2f3644"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill",
   "stylers":[{"color":"#5b6473"}]},
  {"featureType":"administrative.land_parcel","elementType":"labels",
   "stylers":[{"visibility":"off"}]},

  {"featureType":"landscape.man_made","elementType":"geometry",
   "stylers":[{"color":"#eceff3"}]},
  {"featureType":"landscape.natural","elementType":"geometry",
   "stylers":[{"color":"#eaf1e6"}]},

  {"featureType":"poi","stylers":[{"visibility":"on"}]},
  {"featureType":"poi","elementType":"labels.icon",
   "stylers":[{"visibility":"on"},{"saturation":-25}]},
  {"featureType":"poi","elementType":"labels.text.fill",
   "stylers":[{"color":"#6f7889"}]},

  {"featureType":"poi.business","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.business","elementType":"labels.text.fill",
   "stylers":[{"color":"#7b8494"}]},

  {"featureType":"poi.attraction","elementType":"labels.text.fill",
   "stylers":[{"color":"#8a6f52"}]},
  {"featureType":"poi.park","elementType":"geometry",
   "stylers":[{"color":"#d9ecd4"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill",
   "stylers":[{"color":"#5f8a55"}]},
  {"featureType":"poi.medical","elementType":"geometry",
   "stylers":[{"color":"#fbe4e6"}]},
  {"featureType":"poi.medical","elementType":"labels.text.fill",
   "stylers":[{"color":"#a85a62"}]},
  {"featureType":"poi.school","elementType":"geometry",
   "stylers":[{"color":"#f6eede"}]},
  {"featureType":"poi.school","elementType":"labels.text.fill",
   "stylers":[{"color":"#8a7550"}]},
  {"featureType":"poi.place_of_worship","elementType":"labels.text.fill",
   "stylers":[{"color":"#7d7290"}]},
  {"featureType":"poi.sports_complex","elementType":"labels.text.fill",
   "stylers":[{"color":"#5f7f8a"}]},
  {"featureType":"poi.government","elementType":"labels.text.fill",
   "stylers":[{"color":"#5f7091"}]},

  {"featureType":"road","elementType":"geometry.fill",
   "stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.stroke",
   "stylers":[{"color":"#e2e6ec"}]},
  {"featureType":"road","elementType":"labels.text.fill",
   "stylers":[{"color":"#6e7686"}]},
  {"featureType":"road.arterial","elementType":"geometry.stroke",
   "stylers":[{"color":"#dbe0e8"}]},
  {"featureType":"road.highway","elementType":"geometry.fill",
   "stylers":[{"color":"#ffe9b8"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke",
   "stylers":[{"color":"#f0cf86"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill",
   "stylers":[{"color":"#6a6350"}]},
  {"featureType":"road.local","elementType":"labels.text.fill",
   "stylers":[{"color":"#828a99"}]},

  {"featureType":"transit","stylers":[{"visibility":"on"}]},
  {"featureType":"transit","elementType":"labels.icon",
   "stylers":[{"visibility":"on"},{"saturation":-20}]},
  {"featureType":"transit.line","elementType":"geometry",
   "stylers":[{"color":"#dfe3e9"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill",
   "stylers":[{"color":"#5f7091"}]},

  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#bfdff2"}]},
  {"featureType":"water","elementType":"labels.text.fill",
   "stylers":[{"color":"#6c96b5"}]}
]
''';

  static const String dark = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0a1a30"}]},
  {"elementType":"labels.text.stroke",
   "stylers":[{"color":"$_halo"},{"weight":2.5}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"$_neighbourhood"}]},

  {"featureType":"administrative","elementType":"geometry",
   "stylers":[{"color":"#1f2b55"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill",
   "stylers":[{"color":"#d6dff2"}]},
  {"featureType":"administrative.province","elementType":"labels.text.fill",
   "stylers":[{"color":"#b7c4de"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill",
   "stylers":[{"color":"$_locality"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill",
   "stylers":[{"color":"$_neighbourhood"}]},
  {"featureType":"administrative.land_parcel","elementType":"labels",
   "stylers":[{"visibility":"off"}]},

  {"featureType":"poi","stylers":[{"visibility":"on"}]},
  {"featureType":"poi","elementType":"labels.icon",
   "stylers":[{"visibility":"on"},{"saturation":-30},{"lightness":-10}]},
  {"featureType":"poi","elementType":"labels.text.fill",
   "stylers":[{"color":"#8fa0bd"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.business","elementType":"labels.text.fill",
   "stylers":[{"color":"#7e8fac"}]},
  {"featureType":"poi.attraction","elementType":"labels.text.fill",
   "stylers":[{"color":"#c2a98f"}]},
  {"featureType":"poi.medical","elementType":"labels.text.fill",
   "stylers":[{"color":"#c68f99"}]},
  {"featureType":"poi.school","elementType":"labels.text.fill",
   "stylers":[{"color":"#bda87f"}]},
  {"featureType":"poi.park","elementType":"geometry",
   "stylers":[{"color":"#0d2a2c"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill",
   "stylers":[{"color":"#6fae8f"}]},

  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#152546"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill",
   "stylers":[{"color":"$_street"}]},
  {"featureType":"road.arterial","elementType":"geometry",
   "stylers":[{"color":"#1b2f57"}]},
  {"featureType":"road.arterial","elementType":"labels.text.fill",
   "stylers":[{"color":"#93a3c2"}]},
  {"featureType":"road.highway","elementType":"geometry",
   "stylers":[{"color":"#23386a"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke",
   "stylers":[{"color":"#0e54cf"},{"weight":0.4}]},
  {"featureType":"road.highway","elementType":"labels.text.fill",
   "stylers":[{"color":"#aebbd6"}]},

  {"featureType":"transit","elementType":"labels.icon",
   "stylers":[{"visibility":"on"},{"saturation":-30},{"lightness":-10}]},
  {"featureType":"transit.line","elementType":"geometry",
   "stylers":[{"color":"#1a2540"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill",
   "stylers":[{"color":"#8d9bba"}]},

  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#04101f"}]},
  {"featureType":"water","elementType":"labels.text.fill",
   "stylers":[{"color":"#3a6091"}]}
]
''';

  /// The SOS map.
  ///
  /// Same ground, opposite priorities. Hospitals, police stations and
  /// pharmacies get their icons back and their names brightened, because on
  /// this screen a person is looking for a *building*, not for a face — and
  /// the fastest possible answer is one they can see without tapping
  /// anything.
  ///
  /// Business POIs stay off. A chemist matters at three in the morning; a
  /// showroom does not.
  static const String emergency = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0a1a30"}]},
  {"elementType":"labels.text.stroke",
   "stylers":[{"color":"$_halo"},{"weight":2.5}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"$_neighbourhood"}]},

  {"featureType":"administrative","elementType":"geometry",
   "stylers":[{"color":"#1f2b55"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill",
   "stylers":[{"color":"$_locality"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill",
   "stylers":[{"color":"$_neighbourhood"}]},
  {"featureType":"administrative.land_parcel","elementType":"labels",
   "stylers":[{"visibility":"off"}]},

  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},

  {"featureType":"poi.medical","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels.text.fill",
   "stylers":[{"color":"#ff9db1"}]},
  {"featureType":"poi.medical","elementType":"geometry",
   "stylers":[{"color":"#2a1520"}]},

  {"featureType":"poi.government","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.government","elementType":"labels.text.fill",
   "stylers":[{"color":"#9dc0ff"}]},

  {"featureType":"poi.park","elementType":"geometry",
   "stylers":[{"color":"#0d2a2c"}]},

  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#152546"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill",
   "stylers":[{"color":"$_street"}]},
  {"featureType":"road.arterial","elementType":"geometry",
   "stylers":[{"color":"#1b2f57"}]},
  {"featureType":"road.highway","elementType":"geometry",
   "stylers":[{"color":"#23386a"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke",
   "stylers":[{"color":"#0e54cf"},{"weight":0.4}]},
  {"featureType":"road.highway","elementType":"labels.text.fill",
   "stylers":[{"color":"#aebbd6"}]},

  {"featureType":"transit","elementType":"labels.icon",
   "stylers":[{"visibility":"off"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill",
   "stylers":[{"color":"#8d9bba"}]},

  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#04101f"}]},
  {"featureType":"water","elementType":"labels.text.fill",
   "stylers":[{"color":"#3a6091"}]}
]
''';
}

/*
|------------------------------------------------------------------------------
| Chrome
|------------------------------------------------------------------------------
*/

/// The colours the floating controls use, chosen by which map is underneath.
///
/// The rest of SFamily is dark navy glass, and the instinct is to carry that
/// onto the map screen for consistency. It is the wrong instinct: a dark card
/// over a daylight map is a hole, exactly the way a bright map in a dark app
/// is a hole. Contrast is what makes floating chrome legible, and which
/// direction the contrast runs depends entirely on the ground.
///
/// So the chrome follows the map rather than the app. On the night map it is
/// the navy glass everything else uses; on the daylight map it is white. The
/// app's accent colours are the same in both, which is what keeps it feeling
/// like one product.
class MapPalette {
  const MapPalette({
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.shadow,
    required this.accent,
  });

  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color shadow;
  final Color accent;

  /// Over the daylight map.
  static const MapPalette day = MapPalette(
    surface: Colors.white,
    border: Color(0x14101828),
    textPrimary: Color(0xFF1B2430),
    textMuted: Color(0xFF69748A),
    shadow: Color(0x1F0E1B2A),
    accent: Color(0xFF12A66B),
  );

  /// Over the night map.
  static const MapPalette night = MapPalette(
    surface: Color(0xF2011D2F),
    border: AppColors.glassBorder,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
    shadow: Color(0x66000000),
    accent: AppColors.mint,
  );

  static MapPalette of(bool night) => night ? MapPalette.night : MapPalette.day;

  /// The ring colour a marker gets in this palette.
  ///
  /// Slightly different greens by design: the daylight accent is darker so it
  /// holds up against white, and mint would wash out over a pale road.
  Color ringFor({required bool isMe, required bool stale}) {
    if (stale) return const Color(0xFF9AA5B5);
    if (isMe) return const Color(0xFF1E7BE8);

    return accent;
  }
}
