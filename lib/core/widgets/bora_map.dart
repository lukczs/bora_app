import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app/env.dart';
import '../map/google_map_view.dart';
import '../map/map_types.dart';
import '../map/osm_map_view.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';

export '../map/map_types.dart';

/// Mapa do Bora. Usa o Google Maps quando o app é gerado com a chave
/// (MAPS_API_KEY no GitHub); sem chave, usa o mapa escuro do OpenStreetMap.
/// As telas falam só com este widget, então trocar de mapa não mexe nelas.
class BoraMap extends StatelessWidget {
  const BoraMap({
    super.key,
    this.controller,
    this.center = const LatLng(-15.79, -47.88),
    this.zoom = 12,
    this.fitPoints,
    this.pins = const [],
    this.lines = const [],
    this.interactive = true,
    this.padding = EdgeInsets.zero,
    this.onMove,
    this.onMoveStart,
    this.onIdle,
    this.onTap,
  });

  final BoraMapController? controller;
  final LatLng center;
  final double zoom;

  /// Se informado, o mapa abre enquadrando estes pontos.
  final List<LatLng>? fitPoints;
  final List<MapPin> pins;
  final List<MapLine> lines;
  final bool interactive;

  /// Área coberta por elementos por cima do mapa (bottom sheet, barra do topo).
  /// O enquadramento e o logo do mapa respeitam esse espaço.
  final EdgeInsets padding;

  /// A cada movimento da câmera.
  final void Function(MapView view)? onMove;
  final VoidCallback? onMoveStart;

  /// Quando a câmera para (com os limites visíveis).
  final void Function(MapView view)? onIdle;
  final void Function(LatLng point)? onTap;

  @override
  Widget build(BuildContext context) {
    return Env.googleMapsEnabled
        ? GoogleMapView(
            controller: controller,
            center: center,
            zoom: zoom,
            fitPoints: fitPoints,
            pins: pins,
            lines: lines,
            interactive: interactive,
            padding: padding,
            onMove: onMove,
            onMoveStart: onMoveStart,
            onIdle: onIdle,
            onTap: onTap,
          )
        : OsmMapView(
            controller: controller,
            center: center,
            zoom: zoom,
            fitPoints: fitPoints,
            pins: pins,
            lines: lines,
            interactive: interactive,
            padding: padding,
            onMove: onMove,
            onMoveStart: onMoveStart,
            onIdle: onIdle,
            onTap: onTap,
          );
  }
}

// ---------------------------------------------------------------------------
// Atalhos para montar marcadores e linhas
// ---------------------------------------------------------------------------

/// Parada de ônibus. Com [name], mostra o nome ao lado (use com zoom alto).
MapPin stopPin(String id, LatLng point, {String? name, VoidCallback? onTap}) =>
    MapPin(id: 'stop-$id', point: point, kind: name == null ? PinKind.stop : PinKind.stopNamed, label: name, onTap: onTap);

/// Embarque/desembarque em destaque.
MapPin highlightPin(String id, LatLng point, String label, {VoidCallback? onTap}) =>
    MapPin(id: 'hl-$id', point: point, kind: PinKind.highlight, label: label, onTap: onTap);

MapPin carPin(String id, LatLng point, {double? heading, bool mine = false, VoidCallback? onTap}) =>
    MapPin(id: 'car-$id', point: point, kind: mine ? PinKind.carMine : PinKind.car, heading: heading, onTap: onTap);

MapPin youPin(LatLng point) => MapPin(id: 'you', point: point, kind: PinKind.you);
MapPin originPin(LatLng point) => MapPin(id: 'origin', point: point, kind: PinKind.origin);
MapPin destinationPin(LatLng point) => MapPin(id: 'destination', point: point, kind: PinKind.destination);

MapLine routeLine(String id, List<LatLng> points, {bool faint = false}) => MapLine(id: id, points: points, faint: faint);

/// Pin fixo no centro da tela para "Escolher no mapa". Sobe enquanto o mapa se move.
class CenterPin extends StatelessWidget {
  const CenterPin({super.key, this.lifted = false, this.bottomInset = 0});
  final bool lifted;

  /// Mesmo valor do padding inferior do mapa, para o pin ficar no centro real.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, -23),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSlide(
                  duration: const Duration(milliseconds: 150),
                  offset: Offset(0, lifted ? -.35 : 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.text,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.night, width: 8),
                          boxShadow: Shadows.soft,
                        ),
                      ),
                      Container(width: 3, height: 18, color: AppColors.text),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: lifted ? 1 : 0,
                  child: Container(
                    width: 8,
                    height: 4,
                    decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(4)),
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
