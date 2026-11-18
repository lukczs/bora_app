import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

/// O estilo do mapa (assets/map/bora_dark.json) precisa ser lido inteiro:
/// camada que o leitor não entende some do mapa sem aviso.
void main() {
  test('estilo escuro do mapa: todas as camadas são lidas', () {
    final json = jsonDecode(File('assets/map/bora_dark.json').readAsStringSync()) as Map<String, dynamic>;
    final theme = ThemeReader(logger: const Logger.console()).read(json);
    expect(theme.layers.length, (json['layers'] as List).length);
    expect(theme.tileSources, {'openmaptiles'});
  });
}
