import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Mapa base vetorial do OpenFreeMap (grátis, sem chave e sem limite),
/// pintado com o estilo escuro do Bora em assets/map/bora_dark.json.
///
/// O endereço dos blocos do OpenFreeMap muda a cada atualização semanal,
/// então ele é lido do TileJSON (o "url" da fonte no estilo) ao abrir o app.
class VectorBase {
  const VectorBase(this.theme, this.providers);

  final vtr.Theme theme;
  final TileProviders providers;

  static const attribution = '© OpenFreeMap © OpenMapTiles © OpenStreetMap';

  /// Já carregado (para o mapa abrir sem piscar depois da primeira vez).
  static VectorBase? ready;
  static Future<VectorBase?>? _loading;

  /// Carrega uma vez; se falhar (sem internet, servidor fora), tenta de novo
  /// na próxima vez que um mapa abrir.
  static Future<VectorBase?> load() => _loading ??= _load().then((b) {
        ready = b;
        if (b == null) _loading = null;
        return b;
      });

  static Future<VectorBase?> _load() async {
    try {
      final style = jsonDecode(await rootBundle.loadString('assets/map/bora_dark.json')) as Map<String, dynamic>;
      final providers = <String, VectorTileProvider>{};
      for (final source in (style['sources'] as Map<String, dynamic>).entries) {
        final url = (source.value as Map<String, dynamic>)['url'] as String;
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) return null;
        final tileJson = jsonDecode(res.body) as Map<String, dynamic>;
        final tiles = (tileJson['tiles'] as List).cast<String>();
        if (tiles.isEmpty) return null;
        providers[source.key] = NetworkVectorTileProvider(
          urlTemplate: tiles.first,
          maximumZoom: (tileJson['maxzoom'] as num?)?.toInt() ?? 14,
          minimumZoom: 0,
        );
      }
      final theme = vtr.ThemeReader().read(style);
      return VectorBase(theme, TileProviders(providers));
    } catch (_) {
      return null;
    }
  }
}
