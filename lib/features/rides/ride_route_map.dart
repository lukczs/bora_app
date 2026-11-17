import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../core/widgets/bora_map.dart';

/// Mapa de uma viagem: desenha a rota real (do servidor) quando existe,
/// ou os pontos do grafo antigo como plano B.
class RideRouteMap extends ConsumerStatefulWidget {
  const RideRouteMap({super.key, required this.rideId, required this.fallback, this.markers = const [], this.interactive = true});
  final String rideId;
  final List<LatLng> fallback;
  final List<Marker> markers;
  final bool interactive;

  @override
  ConsumerState<RideRouteMap> createState() => _RideRouteMapState();
}

class _RideRouteMapState extends ConsumerState<RideRouteMap> {
  late final Future<List<LatLng>> _route = ref.read(storeProvider).rideRoute(widget.rideId).catchError((_) => <LatLng>[]);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LatLng>>(
      future: _route,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final pts = (snap.data?.isNotEmpty ?? false) ? snap.data! : widget.fallback;
        return BoraMap(
          interactive: widget.interactive,
          fitPoints: [...pts, for (final m in widget.markers) m.point],
          fitPadding: const EdgeInsets.all(32),
          polylines: pts.length > 1 ? boraRoute(pts) : const [],
          markers: widget.markers,
        );
      },
    );
  }
}
