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

  // Em 2026-11-24 a HeiGIT (dona da OpenRouteService) desativou de vez o
  // domínio antigo api.openrouteservice.org e moveu tudo pra api.heigit.org
  // num caminho por serviço. A chave continua a mesma, só mudou a URL.
  static const _base = 'https://api.heigit.org/openrouteservice';
  static const _peliasBase = 'https://api.heigit.org/pelias/v1';

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

  /// Rota para a navegação: passa pelos pontos em ordem e traz as
  /// instruções curva a curva em português.
  Future<NavRoute> navigate(List<LatLng> points) async {
    _requireKey();
    // Pontos repetidos (parada em cima do destino, por exemplo) atrapalham a rota.
    final pts = <LatLng>[];
    for (final p in points) {
      if (pts.isEmpty || const Distance().as(LengthUnit.Meter, pts.last, p) > 25) pts.add(p);
    }
    if (pts.length < 2) pts.add(points.last);
    final r = await _http
        .post(
          Uri.parse('$_base/v2/directions/driving-car/geojson'),
          headers: _headers,
          body: jsonEncode({
            'coordinates': [
              for (final p in pts.take(50)) [p.longitude, p.latitude],
            ],
            'instructions': true,
            'language': 'pt',
            'units': 'm',
          }),
        )
        .timeout(const Duration(seconds: 15));
    _check(r);
    final feature = (jsonDecode(r.body)['features'] as List).first as Map<String, dynamic>;
    final coords = (feature['geometry']['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    final props = feature['properties'] as Map<String, dynamic>;
    final summary = props['summary'] as Map<String, dynamic>? ?? const {};
    final steps = <NavStep>[];
    final legEnds = <int>[];
    for (final seg in (props['segments'] as List? ?? const [])) {
      final segSteps = (seg as Map)['steps'] as List? ?? const [];
      for (final st in segSteps) {
        final wp = (st as Map)['way_points'] as List;
        steps.add(NavStep(
          type: (st['type'] as num?)?.toInt() ?? 6,
          instruction: st['instruction'] as String? ?? '',
          street: (st['name'] as String?)?.replaceAll('-', '').trim() ?? '',
          distanceM: (st['distance'] as num?)?.toDouble() ?? 0,
          durationS: (st['duration'] as num?)?.toDouble() ?? 0,
          from: (wp[0] as num).toInt(),
          to: (wp[1] as num).toInt(),
        ));
      }
      if (segSteps.isNotEmpty) legEnds.add(steps.last.to);
    }
    return NavRoute(
      points: coords,
      steps: steps,
      legEnds: legEnds,
      distanceM: (summary['distance'] as num?)?.round() ?? 0,
      duration: Duration(seconds: (summary['duration'] as num?)?.round() ?? 0),
    );
  }

  /// Sugestões enquanto a pessoa digita.
  /// Busca de lugares: primeiro no Mapbox (acha comércio pequeno, tipo
  /// padaria e loja), depois na OpenRouteService se o Mapbox não achar ou falhar.
  Future<List<Place>> autocomplete(String text, {LatLng? near}) async {
    if (text.trim().length < 3) return const [];
    if (Env.mapboxToken.isNotEmpty) {
      try {
        final found = await _mapbox(text.trim(), near);
        if (found.isNotEmpty) return found;
      } catch (_) {
        // sem Mapbox agora: segue para a OpenRouteService
      }
    }
    return _orsAutocomplete(text, near: near);
  }

  Future<List<Place>> _mapbox(String text, LatLng? near) async {
    final r = await _http.get(
      Uri.parse('https://api.mapbox.com/search/searchbox/v1/forward').replace(queryParameters: {
        'q': text,
        'access_token': Env.mapboxToken,
        'language': 'pt',
        'country': 'BR',
        'limit': '8',
        'bbox': '$_minLon,$_minLat,$_maxLon,$_maxLat',
        if (near != null) 'proximity': '${near.longitude},${near.latitude}',
      }),
    ).timeout(const Duration(seconds: 8));
    if (r.statusCode >= 400) throw Exception('mapbox ${r.statusCode}');
    final features = (jsonDecode(r.body)['features'] as List? ?? const []);
    return [
      for (final f in features)
        if ((f as Map)['geometry']?['coordinates'] is List)
          Place(
            label: (f['properties']?['name'] as String?) ?? text,
            detail: (f['properties']?['full_address'] ?? f['properties']?['place_formatted']) as String?,
            point: LatLng(((f['geometry']['coordinates'] as List)[1] as num).toDouble(),
                ((f['geometry']['coordinates'] as List)[0] as num).toDouble()),
          ),
    ];
  }

  Future<List<Place>> _orsAutocomplete(String text, {LatLng? near}) async {
    _requireKey();
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
        .get(Uri.parse('$_peliasBase/autocomplete').replace(queryParameters: q), headers: _headers)
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
              Uri.parse('$_peliasBase/reverse').replace(queryParameters: {
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

/// Rota da navegação: linha, instruções e onde termina cada trecho (parada).
class NavRoute {
  const NavRoute({required this.points, required this.steps, required this.legEnds, required this.distanceM, required this.duration});
  final List<LatLng> points;
  final List<NavStep> steps;

  /// Índice (em [points]) de onde termina cada trecho entre paradas.
  final List<int> legEnds;
  final int distanceM;
  final Duration duration;
}

/// Uma manobra. [type] segue a OpenRouteService:
/// 0 esquerda, 1 direita, 2 esquerda forte, 3 direita forte, 4 leve à esquerda,
/// 5 leve à direita, 6 em frente, 7 entrar na rotatória, 8 sair da rotatória,
/// 9 retorno, 10 chegada, 11 partida, 12 mantenha à esquerda, 13 mantenha à direita.
class NavStep {
  const NavStep({
    required this.type,
    required this.instruction,
    required this.street,
    required this.distanceM,
    required this.durationS,
    required this.from,
    required this.to,
  });
  final int type;
  final String instruction;
  final String street;
  final double distanceM;
  final double durationS;
  final int from;
  final int to;
}
