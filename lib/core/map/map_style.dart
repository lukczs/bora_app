/// Estilo escuro do Google Maps nas cores do Bora.
/// Ruas e bairros com texto claro e contorno escuro (legível), comércio e
/// paradas do Google escondidos (o Bora desenha as próprias paradas).
const boraMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#141d33"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#cbd5e1"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#0f172a"}, {"weight": 3}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},

  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#2c3a5c"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "administrative.neighborhood", "elementType": "labels.text.fill", "stylers": [{"color": "#94a3b8"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},

  {"featureType": "landscape.man_made", "elementType": "geometry", "stylers": [{"color": "#18223b"}]},
  {"featureType": "landscape.natural", "elementType": "geometry", "stylers": [{"color": "#131c30"}]},

  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#1b2540"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#8a9bb5"}]},
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.medical", "elementType": "labels", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.school", "elementType": "labels", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#14302a"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#6ea58a"}]},

  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2a3858"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#0f172a"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#e2e8f0"}]},
  {"featureType": "road.arterial", "elementType": "geometry.fill", "stylers": [{"color": "#33436a"}]},
  {"featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{"color": "#3d5182"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.local", "elementType": "labels.text.fill", "stylers": [{"color": "#b6c3d6"}]},

  {"featureType": "transit", "stylers": [{"visibility": "off"}]},

  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0c2747"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#5b7aa0"}]}
]
''';
