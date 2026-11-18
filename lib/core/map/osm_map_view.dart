import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import 'map_types.dart';
import 'stop_pin.dart';
import 'vector_base.dart';

/// Mapa sem chave do Google: base vetorial escura do OpenFreeMap (visual
/// limpo, estilo Moovit). Se ela não carregar, cai no OpenStreetMap padrão.
class OsmMapView extends StatefulWidget {
  const OsmMapView({
    super.key,
    required this.controller,
    required this.center,
    required this.zoom,
    required this.fitPoints,
    required this.pins,
    required this.lines,
    required this.interactive,
    required this.padding,
    this.onMove,
    this.onMoveStart,
    this.onIdle,
    this.onTap,
  });

  final BoraMapController? controller;
  final LatLng center;
  final double zoom;
  final List<LatLng>? fitPoints;
  final List<MapPin> pins;
  final List<MapLine> lines;
  final bool interactive;
  final EdgeInsets padding;
  final void Function(MapView view)? onMove;
  final VoidCallback? onMoveStart;
  final void Function(MapView view)? onIdle;
  final void Function(LatLng point)? onTap;

  @override
  State<OsmMapView> createState() => _OsmMapViewState();
}

class _OsmMapViewState extends State<OsmMapView> implements BoraMapDelegate {
  final _map = MapController();
  Timer? _idle;
  bool _moving = false;
  VectorBase? _base = VectorBase.ready;
  bool _baseFailed = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    if (_base == null) {
      VectorBase.load().then((b) {
        if (mounted) {
          setState(() {
            _base = b;
            _baseFailed = b == null;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant OsmMapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.detach(this);
      widget.controller?.attach(this);
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    widget.controller?.detach(this);
    _map.dispose();
    super.dispose();
  }

  EdgeInsets get _fitPadding => widget.padding + const EdgeInsets.all(40);

  @override
  Future<void> moveTo(LatLng p, {double? zoom}) async => _map.move(p, zoom ?? _map.camera.zoom);

  @override
  Future<void> fit(List<LatLng> points) async {
    if (points.length == 1) return moveTo(points.first, zoom: 15);
    _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: _fitPadding, maxZoom: 17));
  }

  @override
  Future<void> follow(LatLng p, {required double heading, double zoom = 17}) async {
    // No flutter_map a rotação é no sentido horário; para a frente do carro
    // ficar para cima, gira ao contrário do rumo.
    _map.rotate(-heading);
    final pad = widget.padding;
    _map.move(p, zoom, offset: Offset(0, (pad.top - pad.bottom) / 2));
  }

  @override
  Future<void> resetBearing() async => _map.rotate(0);

  void _onPos(MapCamera cam, bool gesture) {
    if (!_moving) {
      _moving = true;
      widget.onMoveStart?.call();
    }
    widget.onMove?.call(MapView(center: cam.center, zoom: cam.zoom));
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 350), () {
      _moving = false;
      final c = _map.camera;
      final b = c.visibleBounds;
      widget.onIdle?.call(MapView(
        center: c.center,
        zoom: c.zoom,
        bounds: GeoBounds(south: b.south, west: b.west, north: b.north, east: b.east),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final fp = widget.fitPoints;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: widget.zoom,
        initialCameraFit: fp != null && fp.length > 1
            ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(fp), padding: _fitPadding, maxZoom: 17)
            : null,
        minZoom: 9,
        maxZoom: 19,
        backgroundColor: _baseFailed ? const Color(0xFFE8E4DC) : const Color(0xFF0F172A),
        onPositionChanged: _onPos,
        onMapReady: () => _onPos(_map.camera, false),
        onTap: widget.onTap == null ? null : (_, p) => widget.onTap!(p),
        interactionOptions: InteractionOptions(
          flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        if (_base != null)
          VectorTileLayer(
            theme: _base!.theme,
            tileProviders: _base!.providers,
            layerMode: VectorTileLayerMode.raster,
            maximumZoom: 19,
            fileCacheTtl: const Duration(days: 14),
          )
        else if (_baseFailed)
          TileLayer(
            // Reserva da reserva: OpenStreetMap padrão, sem chave.
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'br.com.bora',
            maxNativeZoom: 19,
            tileBuilder: _softTiles,
          ),
        PolylineLayer(polylines: [
          for (final l in widget.lines) ...[
            Polyline(points: l.points, strokeWidth: l.faint ? 5 : 8, color: AppColors.night),
            Polyline(points: l.points, strokeWidth: l.faint ? 3 : 5, color: l.faint ? const Color(0x9922C55E) : AppColors.green),
          ],
        ]),
        MarkerLayer(markers: [for (final p in widget.pins) _marker(p)]),
        SimpleAttributionWidget(
          source: Text(_base != null ? VectorBase.attribution : '© OpenStreetMap', style: const TextStyle(fontSize: 10)),
          backgroundColor: AppColors.scrim,
          alignment: Alignment.bottomLeft,
        ),
      ],
    );
  }

  Marker _marker(MapPin p) {
    Widget tap(Widget child) => p.onTap == null ? child : GestureDetector(onTap: p.onTap, child: child);
    switch (p.kind) {
      case PinKind.stop:
        return Marker(
          point: p.point,
          width: StopPin.size.width,
          height: StopPin.size.height,
          alignment: Alignment.topCenter,
          rotate: true,
          child: tap(const StopPinIcon()),
        );
      case PinKind.stopNamed:
        // Nome numa etiqueta escura logo acima do ícone de parada.
        return Marker(
          point: p.point,
          width: 200,
          height: 66,
          alignment: Alignment.topCenter,
          rotate: true,
          child: tap(Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.line),
                  boxShadow: Shadows.soft,
                ),
                child: Text(p.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
              const SizedBox(height: 2),
              const StopPinIcon(),
            ],
          )),
        );
      case PinKind.highlight:
        final hl = p.kind == PinKind.highlight;
        return Marker(
          point: p.point,
          width: 200,
          height: 42,
          alignment: Alignment.topCenter,
          rotate: true,
          child: tap(Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: hl ? AppColors.green : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: Shadows.soft,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!hl) ...[const _BusBadge(size: 16), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(p.label ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: hl ? AppColors.night : AppColors.text)),
                  ),
                ]),
              ),
              CustomPaint(size: const Size(12, 7), painter: _Pointer(hl ? AppColors.green : AppColors.surfaceRaised)),
            ],
          )),
        );
      case PinKind.car:
      case PinKind.carMine:
        final mine = p.kind == PinKind.carMine;
        return Marker(
          point: p.point,
          width: 38,
          height: 38,
          child: tap(Transform.rotate(
            angle: (p.heading ?? 0) * math.pi / 180,
            child: Container(
              decoration: BoxDecoration(
                color: mine ? AppColors.green : AppColors.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: mine ? AppColors.night : AppColors.green, width: 2),
                boxShadow: Shadows.soft,
              ),
              child: Icon(Icons.directions_car_filled, size: 19, color: mine ? AppColors.night : AppColors.text),
            ),
          )),
        );
      case PinKind.you:
        return Marker(
          point: p.point,
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
      case PinKind.origin:
        return Marker(
          point: p.point,
          width: 16,
          height: 16,
          child: Container(
            decoration: BoxDecoration(
                color: AppColors.text, shape: BoxShape.circle, border: Border.all(color: AppColors.night, width: 3)),
          ),
        );
      case PinKind.destination:
        return Marker(
          point: p.point,
          width: 20,
          height: 20,
          child: Container(decoration: BoxDecoration(color: AppColors.text, border: Border.all(color: AppColors.night, width: 3))),
        );
    }
  }
}

class _BusBadge extends StatelessWidget {
  const _BusBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(size * .28),
          border: Border.all(color: AppColors.night, width: 1.5),
        ),
        child: Icon(Icons.directions_bus_rounded, size: size * .66, color: AppColors.night),
      );
}

class _Pointer extends CustomPainter {
  _Pointer(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        ui.Path()
          ..moveTo(0, 0)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(size.width, 0)
          ..close(),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Pointer old) => old.color != color;
}

/// Tira um pouco da saturação do OSM para as cores do Bora (verde da rota,
/// carros e paradas) se destacarem, mantendo os nomes nítidos.
Widget _softTiles(BuildContext context, Widget tile, TileImage image) => ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.75, 0.2, 0.05, 0, 0, //
        0.1, 0.85, 0.05, 0, 0, //
        0.1, 0.2, 0.7, 0, 0, //
        0, 0, 0, 1, 0,
      ]),
      child: tile,
    );
