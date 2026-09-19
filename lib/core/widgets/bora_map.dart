import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';

/// Mapa real (OpenStreetMap, sem chave de API) com o tema escuro do Bora.
class BoraMap extends StatelessWidget {
  const BoraMap({
    super.key,
    this.controller,
    this.center = const LatLng(-15.72, -47.80),
    this.zoom = 10.5,
    this.fitPoints,
    this.polylines = const [],
    this.markers = const [],
    this.interactive = true,
  });

  final MapController? controller;
  final LatLng center;
  final double zoom;

  /// Se informado, o mapa abre enquadrando estes pontos.
  final List<LatLng>? fitPoints;
  final List<Polyline> polylines;
  final List<Marker> markers;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final fit = fitPoints != null && fitPoints!.length > 1
        ? CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(fitPoints!),
            padding: const EdgeInsets.all(48),
          )
        : null;

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        initialCameraFit: fit,
        minZoom: 9,
        maxZoom: 18,
        backgroundColor: AppColors.night,
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'br.com.bora.alpha',
          tileBuilder: darkModeTileBuilder,
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap', style: TextStyle(fontSize: 10)),
          backgroundColor: Color(0x990F172A),
        ),
      ],
    );
  }
}

Polyline boraRouteLine(List<LatLng> points, {bool faint = false}) => Polyline(
      points: points,
      strokeWidth: faint ? 3 : 5,
      color: faint ? const Color(0x5522C55E) : AppColors.green,
    );

Marker stopMarker(LatLng point, {VoidCallback? onTap, bool highlight = false, String? label}) => Marker(
      point: point,
      width: highlight ? 120 : 30,
      height: highlight ? 56 : 30,
      alignment: highlight ? Alignment.topCenter : Alignment.center,
      child: GestureDetector(
        onTap: onTap,
        child: highlight
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppColors.green, borderRadius: BorderRadius.circular(8)),
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.night, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  const Icon(Icons.location_on, color: AppColors.green, size: 30),
                ],
              )
            : Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.night,
                  border: Border.all(color: AppColors.green, width: 2.5),
                ),
                child: const Icon(Icons.directions_bus_filled, color: AppColors.mint, size: 14),
              ),
      ),
    );

Marker youAreHereMarker(LatLng point) => Marker(
      point: point,
      width: 26,
      height: 26,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF38BDF8),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x8038BDF8), blurRadius: 12)],
        ),
      ),
    );
