import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Mapa real (OpenStreetMap, sem chave de API) com o tema escuro do Bora.
class BoraMap extends StatelessWidget {
  const BoraMap({
    super.key,
    this.controller,
    this.center = const LatLng(-15.79, -47.88),
    this.zoom = 12,
    this.fitPoints,
    this.fitPadding = const EdgeInsets.all(48),
    this.polylines = const [],
    this.markers = const [],
    this.interactive = true,
    this.onPositionChanged,
    this.onMapReady,
    this.onTap,
  });

  final MapController? controller;
  final LatLng center;
  final double zoom;

  /// Se informado, o mapa abre enquadrando estes pontos.
  final List<LatLng>? fitPoints;
  final EdgeInsets fitPadding;
  final List<Polyline> polylines;
  final List<Marker> markers;
  final bool interactive;
  final void Function(MapCamera camera, bool hasGesture)? onPositionChanged;
  final VoidCallback? onMapReady;
  final void Function(LatLng point)? onTap;

  @override
  Widget build(BuildContext context) {
    final fit = fitPoints != null && fitPoints!.length > 1
        ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(fitPoints!), padding: fitPadding)
        : null;

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        initialCameraFit: fit,
        minZoom: 9,
        maxZoom: 18.5,
        backgroundColor: AppColors.night,
        onPositionChanged: onPositionChanged == null ? null : (c, g) => onPositionChanged!(c, g),
        onMapReady: onMapReady,
        onTap: onTap == null ? null : (_, p) => onTap!(p),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'br.com.bora',
          tileBuilder: darkModeTileBuilder,
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
        const SimpleAttributionWidget(
          source: Text('© OpenStreetMap', style: TextStyle(fontSize: 10)),
          backgroundColor: AppColors.scrim,
          alignment: Alignment.bottomLeft,
        ),
      ],
    );
  }
}

/// Rota: traço verde com contorno escuro (fica legível sobre qualquer rua).
List<Polyline> boraRoute(List<LatLng> points, {bool faint = false}) => [
      Polyline(points: points, strokeWidth: faint ? 5 : 8, color: AppColors.night),
      Polyline(points: points, strokeWidth: faint ? 3 : 5, color: faint ? const Color(0x8822C55E) : AppColors.green),
    ];

/// Compatibilidade com telas antigas.
Polyline boraRouteLine(List<LatLng> points, {bool faint = false}) => boraRoute(points, faint: faint).last;

/// Parada: ponto discreto (estilo Moovit). Destacada vira um selo com nome.
Marker stopMarker(LatLng point, {VoidCallback? onTap, bool highlight = false, String? label}) => Marker(
      point: point,
      width: highlight ? 160 : 22,
      height: highlight ? 58 : 22,
      alignment: highlight ? Alignment.topCenter : Alignment.center,
      child: GestureDetector(
        onTap: onTap,
        child: highlight
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(6), boxShadow: Shadows.soft),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: AppColors.text, fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 4),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.night, width: 2.5),
                    ),
                  ),
                ],
              )
            : Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.night,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.green, width: 2.5),
                  ),
                ),
              ),
      ),
    );

/// Carro no mapa (estilo 99): ícone de veículo girado na direção do movimento.
Marker carMarker(LatLng point, {double? heading, bool mine = false, VoidCallback? onTap}) => Marker(
      point: point,
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: onTap,
        child: Transform.rotate(
          angle: (heading ?? 0) * math.pi / 180,
          child: Container(
            decoration: BoxDecoration(
              color: mine ? AppColors.green : AppColors.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(color: mine ? AppColors.night : AppColors.green, width: 2),
              boxShadow: Shadows.soft,
            ),
            child: Icon(Icons.directions_car_filled, size: 18, color: mine ? AppColors.night : AppColors.text),
          ),
        ),
      ),
    );

Marker youAreHereMarker(LatLng point) => Marker(
      point: point,
      width: 22,
      height: 22,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.user,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x8038BDF8), blurRadius: 14, spreadRadius: 2)],
        ),
      ),
    );

/// Bandeira de destino.
Marker destinationMarker(LatLng point) => Marker(
      point: point,
      width: 20,
      height: 20,
      child: Container(
        decoration: BoxDecoration(color: AppColors.text, border: Border.all(color: AppColors.night, width: 3)),
      ),
    );

/// Pin fixo no centro da tela para "Escolher no mapa". Sobe enquanto o mapa se move.
class CenterPin extends StatelessWidget {
  const CenterPin({super.key, this.lifted = false});
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -26),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 150),
            offset: Offset(0, lifted ? -.25 : 0),
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
        ),
      ),
    );
  }
}
