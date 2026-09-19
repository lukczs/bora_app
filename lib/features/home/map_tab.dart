import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../domain/models.dart';

enum _Mode { passenger, driver }

class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});
  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab> {
  final _map = MapController();
  _Mode _mode = _Mode.passenger;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _centerOnMe() async {
    final store = ref.read(storeProvider);
    final real = await store.locate(askPermission: true);
    if (!mounted) return;
    _map.move(store.position, 13.5);
    if (!real) {
      showBoraError(context, 'Sem acesso ao GPS. Usando a Rodoviária do Plano como ponto de partida.');
    }
  }

  void _showStop(Stop stop) {
    final store = ref.read(storeProvider);
    final passing =
        store.openRidePaths.where((path) => path.contains(stop.id) && path.last != stop.id).length;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stop.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(stop.region),
            const SizedBox(height: 12),
            Text(passing == 0
                ? 'Nenhuma viagem aberta passa por aqui agora.'
                : passing == 1
                    ? '1 viagem aberta passa por aqui.'
                    : '$passing viagens abertas passam por aqui.'),
            const SizedBox(height: 18),
            BoraButton(
              label: 'Buscar carona saindo daqui',
              onPressed: () {
                Navigator.of(sheet).pop();
                context.push('/search?pickup=${stop.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final me = store.me;
    final graph = store.graph;
    if (me == null || graph.boardable.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.green));
    }
    final nearest = graph.nearestBoardable(store.position);
    final walk = graph.metersBetween(store.position, nearest.point);
    final hasVehicle = store.myVehicles.isNotEmpty;

    return Stack(
      children: [
        BoraMap(
          controller: _map,
          center: store.position,
          zoom: 12.5,
          polylines: [
            for (final (a, b) in graph.links) boraRouteLine(graph.pointsOf([a, b]), faint: true),
          ],
          markers: [
            for (final s in graph.boardable)
              stopMarker(s.point, onTap: () => _showStop(s), highlight: s.id == nearest.id, label: s.name),
            youAreHereMarker(store.position),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xE60F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text('Oi, ${me.firstName}',
                        style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: const Color(0xE60F172A)),
                  tooltip: 'Centralizar em mim',
                  icon: const Icon(Icons.my_location, color: AppColors.mint),
                  onPressed: _centerOnMe,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xF20F172A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_Mode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: _Mode.passenger, label: Text('Preciso de carona')),
                      ButtonSegment(value: _Mode.driver, label: Text('Vou dirigir')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                ),
                const SizedBox(height: 14),
                if (_mode == _Mode.passenger) ...[
                  Text('Parada mais perto de você: ${nearest.name}',
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                  Text(store.positionIsReal
                      ? 'A $walk m de você'
                      : 'Localização aproximada. Toque na mira para usar o GPS.'),
                  const SizedBox(height: 14),
                  BoraButton(
                    label: 'Buscar carona',
                    onPressed: () => context.push('/search?pickup=${nearest.id}'),
                  ),
                ] else ...[
                  Text(
                    hasVehicle
                        ? 'Informe o destino e as vagas. O Bora calcula a rota e preenche os lugares.'
                        : 'Para oferecer carona, cadastre primeiro o seu carro.',
                    style: const TextStyle(color: AppColors.text),
                  ),
                  const SizedBox(height: 14),
                  BoraButton(
                    label: hasVehicle ? 'Publicar viagem' : 'Cadastrar meu carro',
                    onPressed: () {
                      if (me.identityStatus != VerificationStatus.approved) {
                        showBoraError(context, 'Sua identidade ainda está em verificação.');
                        return;
                      }
                      context.push(hasVehicle ? '/publish' : '/vehicle');
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
