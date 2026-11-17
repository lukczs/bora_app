import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Tipos de marcador do Bora. Cada implementação de mapa desenha do seu jeito.
enum PinKind {
  /// Parada de ônibus comum (ícone pequeno).
  stop,

  /// Parada com o nome ao lado (aparece com zoom alto).
  stopNamed,

  /// Embarque/desembarque destacado, com rótulo.
  highlight,

  car,
  carMine,
  you,
  origin,
  destination,
}

@immutable
class MapPin {
  const MapPin({required this.id, required this.point, required this.kind, this.label, this.heading, this.onTap});
  final String id;
  final LatLng point;
  final PinKind kind;
  final String? label;
  final double? heading;
  final VoidCallback? onTap;
}

@immutable
class MapLine {
  const MapLine({required this.id, required this.points, this.faint = false});
  final String id;
  final List<LatLng> points;
  final bool faint;
}

@immutable
class GeoBounds {
  const GeoBounds({required this.south, required this.west, required this.north, required this.east});
  final double south, west, north, east;

  factory GeoBounds.fromPoints(List<LatLng> pts) {
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final p in pts) {
      if (p.latitude < s) s = p.latitude;
      if (p.latitude > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    return GeoBounds(south: s, west: w, north: n, east: e);
  }
}

/// Onde a câmera está. [bounds] só vem quando o mapa para de mexer.
@immutable
class MapView {
  const MapView({required this.center, required this.zoom, this.bounds});
  final LatLng center;
  final double zoom;
  final GeoBounds? bounds;
}

/// Controle do mapa usado pelas telas (mover, enquadrar).
class BoraMapController {
  _Delegate? _delegate;

  // ignore: use_setters_to_change_properties
  void attach(_Delegate d) => _delegate = d;
  void detach(_Delegate d) {
    if (identical(_delegate, d)) _delegate = null;
  }

  Future<void> moveTo(LatLng p, {double? zoom}) async => _delegate?.moveTo(p, zoom: zoom);
  Future<void> fit(List<LatLng> points) async {
    if (points.isEmpty) return;
    await _delegate?.fit(points);
  }
}

typedef _Delegate = BoraMapDelegate;

abstract class BoraMapDelegate {
  Future<void> moveTo(LatLng p, {double? zoom});
  Future<void> fit(List<LatLng> points);
}
