import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/measure_size.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';

/// Busca de endereço em tela cheia ("Para onde vamos?").
/// Devolve um [Place] com Navigator.pop, ou null se a pessoa voltar.
class PlaceSearchScreen extends ConsumerStatefulWidget {
  const PlaceSearchScreen({super.key, this.title = 'Para onde vamos?', this.hint = 'Buscar endereço ou lugar', this.allowMyLocation = false});
  final String title;
  final String hint;
  final bool allowMyLocation;

  static Future<Place?> open(BuildContext context, {String title = 'Para onde vamos?', String hint = 'Buscar endereço ou lugar', bool allowMyLocation = false}) =>
      Navigator.of(context).push<Place>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlaceSearchScreen(title: title, hint: hint, allowMyLocation: allowMyLocation),
      ));

  @override
  ConsumerState<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends ConsumerState<PlaceSearchScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(v));
  }

  Future<void> _search(String v) async {
    final seq = ++_seq;
    if (v.trim().length < 3) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final store = ref.read(storeProvider);
      final r = await ref.read(routingProvider).autocomplete(v, near: store.position);
      if (seq == _seq && mounted) setState(() => _results = r);
      _error = null;
    } catch (e) {
      if (seq == _seq && mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickOnMap() async {
    final p = await MapPickerScreen.open(context, title: widget.title);
    if (p != null && mounted) Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, Space.sm),
            child: TextField(
              controller: _text,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              style: AppText.subtitle,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : (_text.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _text.clear();
                              _search('');
                            })),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (widget.allowMyLocation)
                  ListRow(
                    icon: Icons.my_location,
                    title: 'Minha localização',
                    subtitle: store.positionIsReal ? 'Usar o GPS' : 'GPS indisponível: usa a Rodoviária do Plano',
                    onTap: () async {
                      await store.locate(askPermission: true);
                      if (context.mounted) {
                        Navigator.of(context).pop(Place(label: 'Minha localização', point: store.position));
                      }
                    },
                  ),
                ListRow(icon: Icons.push_pin_outlined, title: 'Escolher no mapa', subtitle: 'Arraste o mapa até o ponto', onTap: _pickOnMap),
                const Divider(indent: Space.page, endIndent: Space.page),
                if (_error != null)
                  Padding(padding: const EdgeInsets.all(Space.page), child: Text(_error!, style: AppText.body)),
                for (final p in _results)
                  ListRow(
                    icon: Icons.place_outlined,
                    title: p.label,
                    subtitle: (p.detail ?? '').isEmpty ? null : p.detail,
                    trailing: const SizedBox.shrink(),
                    onTap: () => Navigator.of(context).pop(p),
                  ),
                if (_results.isEmpty && _text.text.trim().length >= 3 && !_loading && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(Space.page),
                    child: Text('Nada encontrado. Tente o nome de uma quadra, comércio ou escolha no mapa.', style: AppText.body),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Escolher no mapa": pin fixo no centro, a pessoa arrasta o mapa.
class MapPickerScreen extends ConsumerStatefulWidget {
  const MapPickerScreen({super.key, required this.title, this.start});
  final String title;
  final LatLng? start;

  static Future<Place?> open(BuildContext context, {required String title, LatLng? start}) =>
      Navigator.of(context).push<Place>(MaterialPageRoute(builder: (_) => MapPickerScreen(title: title, start: start)));

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  late LatLng _center;
  Place? _place;
  bool _moving = false;
  double _sheetHeight = 190;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _center = widget.start ?? ref.read(storeProvider).position;
    _resolve();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onMove(MapView v) {
    _center = v.center;
    if (!_moving) setState(() => _moving = true);
  }

  void _onIdle(MapView v) {
    _center = v.center;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _moving = false);
      _resolve();
    });
  }

  Future<void> _resolve() async {
    final seq = ++_seq;
    final at = _center;
    setState(() => _place = null);
    final p = await ref.read(routingProvider).reverse(at);
    if (seq == _seq && mounted) setState(() => _place = p);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          BoraMap(
            center: _center,
            zoom: 16.5,
            padding: EdgeInsets.only(bottom: _sheetHeight),
            onMove: _onMove,
            onIdle: _onIdle,
          ),
          CenterPin(lifted: _moving, bottomInset: _sheetHeight),
          Positioned(
            top: MediaQuery.paddingOf(context).top + Space.sm,
            left: Space.md,
            child: RoundIconButton(icon: Icons.arrow_back, onPressed: () => Navigator.of(context).pop()),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: MeasureSize(
              onChange: (s) => setState(() => _sheetHeight = s.height),
              child: _SheetBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: AppText.label),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      const IconTile(Icons.place, color: AppColors.green),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: _place == null || _moving
                            ? const Text('Procurando endereço…', style: AppText.body)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_place!.label, style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  if ((_place!.detail ?? '').isNotEmpty)
                                    Text(_place!.detail!, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  BoraButton(
                    label: 'Confirmar ponto',
                    onPressed: _moving
                        ? null
                        : () => Navigator.of(context).pop(_place ?? Place(label: 'Ponto no mapa', point: _center)),
                  ),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Caixa de bottom sheet fixa (sobre o mapa).
class _SheetBox extends StatelessWidget {
  const _SheetBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, Space.md + MediaQuery.paddingOf(context).bottom),
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
          boxShadow: Shadows.floating,
        ),
        child: child,
      );
}
