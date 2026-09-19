import 'package:latlong2/latlong.dart';
import '../domain/models.dart';

/// Grafo de paradas carregado do banco (stops + stop_links). O app calcula o
/// menor caminho e o banco valida em publish_ride. Quando entrar uma API de
/// rotas, só este arquivo e a função publish_ride mudam.
class RouteGraph {
  RouteGraph(List<Stop> stops, this.links) : stops = {for (final s in stops) s.id: s} {
    for (final (a, b) in links) {
      if (!this.stops.containsKey(a) || !this.stops.containsKey(b)) continue;
      final d = _meters(a, b);
      (_adj[a] ??= {})[b] = d;
      (_adj[b] ??= {})[a] = d;
    }
  }

  final Map<String, Stop> stops;
  final List<(String, String)> links;
  final Map<String, Map<String, double>> _adj = {};

  static const _distance = Distance();

  double _meters(String a, String b) =>
      _distance.as(LengthUnit.Meter, stops[a]!.point, stops[b]!.point) * 1.25;

  List<Stop> get boardable =>
      stops.values.where((s) => s.boardable).toList()..sort((a, b) => a.name.compareTo(b.name));

  List<String>? shortestPath(String from, String to) {
    if (from == to || !_adj.containsKey(from) || !_adj.containsKey(to)) return null;
    final dist = <String, double>{from: 0};
    final prev = <String, String>{};
    final pending = <String>{from};
    final done = <String>{};

    while (pending.isNotEmpty) {
      final current = pending.reduce((a, b) => dist[a]! <= dist[b]! ? a : b);
      pending.remove(current);
      if (current == to) break;
      done.add(current);
      for (final entry in _adj[current]!.entries) {
        if (done.contains(entry.key)) continue;
        final candidate = dist[current]! + entry.value;
        if (candidate < (dist[entry.key] ?? double.infinity)) {
          dist[entry.key] = candidate;
          prev[entry.key] = current;
          pending.add(entry.key);
        }
      }
    }
    if (!prev.containsKey(to)) return null;

    final path = <String>[to];
    while (path.first != from) {
      path.insert(0, prev[path.first]!);
    }
    return path;
  }

  int distanceAlong(List<String> path, int fromIndex, int toIndex) {
    var total = 0.0;
    for (var i = fromIndex; i < toIndex; i++) {
      total += _meters(path[i], path[i + 1]);
    }
    return total.round();
  }

  List<LatLng> pointsOf(List<String> path) =>
      [for (final id in path) if (stops[id] != null) stops[id]!.point];

  Stop nearestBoardable(LatLng position) => boardable.reduce((a, b) =>
      _distance.as(LengthUnit.Meter, position, a.point) <= _distance.as(LengthUnit.Meter, position, b.point)
          ? a
          : b);

  int metersBetween(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b).round();
}
