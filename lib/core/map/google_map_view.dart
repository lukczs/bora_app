import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import 'map_style.dart';
import 'map_types.dart';
import 'marker_art.dart';

/// Mapa do Google com o estilo escuro do Bora.
class GoogleMapView extends StatefulWidget {
  const GoogleMapView({
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
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

gm.LatLng _g(LatLng p) => gm.LatLng(p.latitude, p.longitude);
LatLng _l(gm.LatLng p) => LatLng(p.latitude, p.longitude);

class _GoogleMapViewState extends State<GoogleMapView> implements BoraMapDelegate {
  gm.GoogleMapController? _ctrl;
  static MarkerArt? _art;
  final Map<String, gm.BitmapDescriptor> _icons = {};
  final Map<String, Offset> _anchors = {};
  gm.CameraPosition? _last;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    _loadIcons();
  }

  @override
  void didUpdateWidget(covariant GoogleMapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.detach(this);
      widget.controller?.attach(this);
    }
    _loadIcons();
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    super.dispose();
  }

  String _key(MapPin p) => '${p.kind}|${p.label ?? ''}';

  Future<void> _loadIcons() async {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final art = _art ??= MarkerArt(dpr);
    final missing = {for (final p in widget.pins) if (!_icons.containsKey(_key(p))) _key(p): p};
    if (missing.isEmpty) return;
    for (final e in missing.entries) {
      final img = await art.image(e.value.kind, label: e.value.label);
      _icons[e.key] = gm.BitmapDescriptor.bytes(img.png, imagePixelRatio: dpr);
      _anchors[e.key] = img.anchor;
    }
    if (mounted) setState(() {});
  }

  @override
  Future<void> moveTo(LatLng p, {double? zoom}) async {
    await _ctrl?.animateCamera(zoom == null ? gm.CameraUpdate.newLatLng(_g(p)) : gm.CameraUpdate.newLatLngZoom(_g(p), zoom));
  }

  @override
  Future<void> fit(List<LatLng> points) async {
    final c = _ctrl;
    if (c == null || points.isEmpty) return;
    if (points.length == 1) return moveTo(points.first, zoom: 15);
    final b = GeoBounds.fromPoints(points);
    // Garante uma área mínima para não dar zoom exagerado em pontos muito próximos.
    const min = .002;
    final bounds = gm.LatLngBounds(
      southwest: gm.LatLng(b.south - min, b.west - min),
      northeast: gm.LatLng(b.north + min, b.east + min),
    );
    await c.animateCamera(gm.CameraUpdate.newLatLngBounds(bounds, 40));
  }

  Future<void> _emitIdle() async {
    final c = _ctrl, pos = _last;
    if (c == null || pos == null || widget.onIdle == null) return;
    try {
      final r = await c.getVisibleRegion();
      widget.onIdle!(MapView(
        center: _l(pos.target),
        zoom: pos.zoom,
        bounds: GeoBounds(
          south: r.southwest.latitude,
          west: r.southwest.longitude,
          north: r.northeast.latitude,
          east: r.northeast.longitude,
        ),
      ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final markers = <gm.Marker>{
      for (final (i, p) in widget.pins.indexed)
        if (_icons[_key(p)] != null)
          gm.Marker(
            markerId: gm.MarkerId(p.id),
            position: _g(p.point),
            icon: _icons[_key(p)]!,
            anchor: _anchors[_key(p)] ?? const Offset(.5, .5),
            rotation: (p.kind == PinKind.car || p.kind == PinKind.carMine) ? (p.heading ?? 0) : 0,
            flat: p.kind == PinKind.car || p.kind == PinKind.carMine,
            zIndexInt: switch (p.kind) {
                  PinKind.stop => 1,
                  PinKind.stopNamed => 2,
                  PinKind.car || PinKind.carMine => 4,
                  PinKind.highlight => 5,
                  _ => 3,
                } *
                    10000 +
                i,
            consumeTapEvents: p.onTap != null,
            onTap: p.onTap,
          ),
    };

    final polylines = <gm.Polyline>{
      for (final l in widget.lines) ...[
        gm.Polyline(
          polylineId: gm.PolylineId('${l.id}-casing'),
          points: [for (final p in l.points) _g(p)],
          width: l.faint ? 6 : 10,
          color: AppColors.night,
          zIndex: 1,
          jointType: gm.JointType.round,
          startCap: gm.Cap.roundCap,
          endCap: gm.Cap.roundCap,
        ),
        gm.Polyline(
          polylineId: gm.PolylineId(l.id),
          points: [for (final p in l.points) _g(p)],
          width: l.faint ? 3 : 6,
          color: l.faint ? const Color(0x9922C55E) : AppColors.green,
          zIndex: 2,
          jointType: gm.JointType.round,
          startCap: gm.Cap.roundCap,
          endCap: gm.Cap.roundCap,
        ),
      ],
    };

    final i = widget.interactive;
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(target: _g(widget.center), zoom: widget.zoom),
      style: boraMapStyle,
      padding: widget.padding,
      markers: markers,
      polylines: polylines,
      liteModeEnabled: false,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      trafficEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: i,
      zoomGesturesEnabled: i,
      minMaxZoomPreference: const gm.MinMaxZoomPreference(9, 19),
      onMapCreated: (c) async {
        _ctrl = c;
        final fp = widget.fitPoints;
        if (fp != null && fp.length > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await fit(fp);
        }
      },
      onCameraMoveStarted: widget.onMoveStart,
      onCameraMove: (pos) {
        _last = pos;
        widget.onMove?.call(MapView(center: _l(pos.target), zoom: pos.zoom));
      },
      onCameraIdle: _emitIdle,
      onTap: widget.onTap == null ? null : (p) => widget.onTap!(_l(p)),
    );
  }
}
