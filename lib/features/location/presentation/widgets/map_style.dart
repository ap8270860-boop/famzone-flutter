/// The map, dressed in the app's colours.
///
/// Google's default map is a bright, high-contrast document designed to be
/// read on its own. Dropped into a deep-navy app it reads as a hole punched
/// in the screen — and worse, it competes with the markers, which are the
/// only part anybody is actually looking at.
///
/// Two styles, because two screens want opposite things from the same map:
///
///  - [dark] is the family map. Quiet. Roads and water for orientation,
///    place names so you can tell where somebody is, and nothing else — a
///    person's face should be the brightest thing on screen.
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
  | So labels are now tiered by importance rather than uniformly dimmed:
  | localities brightest, neighbourhoods next, streets quietest. Icons stay
  | off on the family map (they are business advertising, and they clutter),
  | but the words stay on.
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

  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.attraction","elementType":"labels.text.fill",
   "stylers":[{"color":"#8fa2c2"}]},
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
   "stylers":[{"visibility":"off"}]},
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
