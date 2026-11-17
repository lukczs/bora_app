import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../app/env.dart';
import '../domain/models.dart';

/// Rotas e busca de endereços pela OpenRouteService.
/// A chave entra no build pelo secret ORS_API_KEY (--dart-define).
/// Só o motorista gasta cota de rota (1 chamada por viagem publicada);
/// a busca de caronas roda inteira no Supabase.
class RoutingService {
  RoutingService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _base = 'https://api.openrouteservice.org';

  // Caixa do DF e Entorno: as sugestões ficam por aqui.
  static const _minLon = -48.7, _minLat = -16.5, _maxLon = -47.0, _maxLat = -15.2;

  bool get isConfigured => Env.orsApiKey.isNotEmpty;

  Map<String, String> get _headers => {
        'Authorization': Env.orsApiKey,
        'Accept': 'application/json, application/geo+json',
        'Content-Type': 'application/json',
      };

  void _check(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) throw const BoraException('Chave de rotas inválida.');
    if (r.statusCode == 429) throw const BoraException('Muitas buscas de rota agora. Tente em um minuto.');
    if (r.statusCode >= 400) throw BoraException('Não foi possível calcular a rota (${r.statusCode}).');
  }

  void _requireKey() {
    if (!isConfigured) throw const BoraException('O app foi gerado sem a chave de rotas (ORS_API_KEY).');
  }

  /// Rota de carro entre dois pontos.
  Future<RoutePlan> route(LatLng from, LatLng to) async {
    _requireKey();
    final r = await _http
        .post(
          Uri.parse('$_base/v2/directions/driving-car/geojson'),
          headers: _headers,
          body: jsonEncode({
            'coordinates': [
              [from.longitude, from.latitude],
              [to.longitude, to.latitude],
            ],
            'instructions': false,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _check(r);
    final feature = (jsonDecode(r.body)['features'] as List).first as Map<String, dynamic>;
    final coords = (feature['geometry']['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    final summary = feature['properties']['summary'] as Map<String, dynamic>;
    return RoutePlan(
      points: coords,
      distanceM: (summary['distance'] as num).round(),
      duration: Duration(seconds: (summary['duration'] as num).round()),
      geoJson: {
        'type': 'LineString',
        'coordinates': feature['geometry']['coordinates'],
      },
    );
  }

  /// Sugestões enquanto a pessoa digita.
  Future<List<Place>> autocomplete(String text, {LatLng? near}) async {
    _requireKey();
    if (text.trim().length < 3) return const [];
    final q = <String, String>{
      'text': text.trim(),
      'boundary.country': 'BR',
      'boundary.rect.min_lon': '$_minLon',
      'boundary.rect.min_lat': '$_minLat',
      'boundary.rect.max_lon': '$_maxLon',
      'boundary.rect.max_lat': '$_maxLat',
      'size': '8',
      'lang': 'pt',
      if (near != null) 'focus.point.lon': '${near.longitude}',
      if (near != null) 'focus.point.lat': '${near.latitude}',
    };
    final r = await _http
        .get(Uri.parse('$_base/geocode/autocomplete').replace(queryParameters: q), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _check(r);
    return _places(r.body);
  }

  /// Nome do lugar onde o pin parou.
  Future<Place> reverse(LatLng p) async {
    final fallback = Place(label: 'Ponto no mapa', point: p);
    if (!isConfigured) return fallback;
    try {
      final r = await _http
          .get(
              Uri.parse('$_base/geocode/reverse').replace(queryParameters: {
                'point.lon': '${p.longitude}',
                'point.lat': '${p.latitude}',
                'size': '1',
                'lang': 'pt',
              }),
              headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode >= 400) return fallback;
      final list = _places(r.body);
      return list.isEmpty ? fallback : Place(label: list.first.label, detail: list.first.detail, point: p);
    } catch (_) {
      return fallback;
    }
  }

  List<Place> _places(String body) {
    final features = (jsonDecode(body)['features'] as List? ?? const []);
    return [
      for (final f in features)
        Place(
          label: (f['properties']['name'] ?? f['properties']['label'] ?? 'Lugar') as String,
          detail: [f['properties']['neighbourhood'], f['properties']['locality'] ?? f['properties']['county']]
              .whereType<String>()
              .toSet()
              .join(', '),
          point: LatLng(
            ((f['geometry']['coordinates'] as List)[1] as num).toDouble(),
            ((f['geometry']['coordinates'] as List)[0] as num).toDouble(),
          ),
        ),
    ];
  }
}

class RoutePlan {
  const RoutePlan({required this.points, required this.distanceM, required this.duration, required this.geoJson});
  final List<LatLng> points;
  final int distanceM;
  final Duration duration;
  final Map<String, dynamic> geoJson;
}
