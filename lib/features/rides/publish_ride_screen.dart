import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../data/routing_service.dart';
import '../../domain/models.dart';
import '../places/place_picker.dart';

/// Oferecer carona: origem e destino livres, rota real, paradas descobertas pelo servidor.
/// Com [editRideId], edita só horário, vagas e recorrência (a rota fica como está).
class PublishRideScreen extends ConsumerStatefulWidget {
  const PublishRideScreen({super.key, this.editRideId, this.eventId, this.eventLeg});
  final String? editRideId;

  /// Carona para um evento: 'ida' termina no evento, 'volta' sai dele.
  final String? eventId;
  final String? eventLeg;
  @override
  ConsumerState<PublishRideScreen> createState() => _PublishRideScreenState();
}

class _PublishRideScreenState extends ConsumerState<PublishRideScreen> {
  Place? _origin;
  Place? _destination;
  RoutePlan? _plan;
  int? _demand;
  bool _routing = false;

  String? _vehicleId;
  int _seats = 1;
  late DateTime _departure;
  final Set<int> _weekdays = {};
  final Set<String> _communityIds = {};
  bool _womenOnly = false;
  bool _loading = false;

  bool get _editing => widget.editRideId != null;
  BoraEvent? _event;
  bool get _forEvent => widget.eventId != null;
  bool get _ida => widget.eventLeg != 'volta';

  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider);
    final ride = _editing ? store.myRide(widget.editRideId!) : null;
    if (ride != null) {
      _vehicleId = ride.vehicle.id;
      _seats = ride.seatsTotal;
      _departure = ride.departureAt;
      _weekdays.addAll(ride.recurringDays);
      _communityIds.addAll(ride.communityIds);
      _womenOnly = ride.womenOnly;
    } else {
      _origin = Place(label: 'Minha localização', point: store.position);
      _vehicleId = store.myVehicles.firstOrNull?.id;
      _seats = store.myVehicles.firstOrNull?.seats ?? 1;
      final soon = DateTime.now().add(const Duration(minutes: 30));
      _departure = DateTime(soon.year, soon.month, soon.day, soon.hour, (soon.minute ~/ 5) * 5);
    }
    if (_forEvent) _loadEvent();
  }

  Future<void> _loadEvent() async {
    final store = ref.read(storeProvider);
    final e = await store.event(widget.eventId!);
    if (e == null || !mounted) return;
    final venue = Place(label: e.venueLabel, point: e.point);
    setState(() {
      _event = e;
      if (_ida) {
        _destination = venue;
        final d = e.startsAt.subtract(const Duration(hours: 1));
        _departure = DateTime(d.year, d.month, d.day, d.hour, (d.minute ~/ 5) * 5);
      } else {
        _origin = venue;
        _destination = null;
        _departure = e.endsAt;
      }
    });
    if (_origin != null && _destination != null) await _route();
  }

  Future<void> _pick({required bool origin}) async {
    final p = await PlaceSearchScreen.open(
      context,
      title: origin ? 'De onde você sai?' : 'Para onde você vai?',
      hint: origin ? 'Ponto de partida' : 'Destino',
      allowMyLocation: origin,
    );
    if (p == null || !mounted) return;
    setState(() {
      if (origin) {
        _origin = p;
      } else {
        _destination = p;
      }
      _plan = null;
      _demand = null;
    });
    await _route();
  }

  Future<void> _route() async {
    final o = _origin, d = _destination;
    if (o == null || d == null) return;
    setState(() => _routing = true);
    try {
      final store = ref.read(storeProvider);
      final plan = await ref.read(routingProvider).route(o.point, d.point);
      if (!mounted) return;
      setState(() => _plan = plan);
      final demand = _forEvent
          ? await store.eventDemand(widget.eventId!, widget.eventLeg ?? 'ida', plan.geoJson)
          : await store.demandNearRoute(plan.geoJson);
      if (mounted) setState(() => _demand = demand);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _pickDeparture() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _departure.isBefore(now) ? now : _departure,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_departure));
    if (time == null) return;
    setState(() => _departure = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    final store = ref.read(storeProvider);
    setState(() => _loading = true);
    try {
      if (_editing) {
        await store.updateRide(widget.editRideId!, departureAt: _departure, seats: _seats, recurringDays: _weekdays.toList());
        if (mounted) context.pop();
        return;
      }
      if (_plan == null || _vehicleId == null) {
        showBoraError(context, _vehicleId == null ? 'Cadastre um carro antes.' : 'Defina origem e destino.');
        return;
      }
      if (_forEvent) {
        final r = await store.publishEventRide(
          eventId: widget.eventId!,
          leg: widget.eventLeg ?? 'ida',
          vehicleId: _vehicleId!,
          routeGeoJson: _plan!.geoJson,
          originLabel: _origin!.label,
          destLabel: _destination!.label,
          departureAt: _departure,
          seats: _seats,
          womenOnly: _womenOnly,
        );
        if (!mounted) return;
        showBoraError(context, 'Carona publicada no evento com ${r.stops} pontos de embarque.');
        context.pushReplacement('/my-ride/${r.rideId}');
        return;
      }
      final r = await store.publishRideRoute(
        vehicleId: _vehicleId!,
        routeGeoJson: _plan!.geoJson,
        originLabel: _origin!.label,
        destLabel: _destination!.label,
        departureAt: _departure,
        seats: _seats,
        recurringDays: _weekdays.toList(),
        womenOnly: _womenOnly,
        communityIds: _communityIds.toList(),
      );
      if (!mounted) return;
      showBoraError(context, 'Viagem publicada com ${r.stops} pontos de embarque no caminho.');
      context.pushReplacement('/my-ride/${r.rideId}');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final me = store.me!;
    final vehicles = store.myVehicles;
    final communities = store.myCommunities.where((c) => c.myStatus == MemberStatus.active).toList();
    // Cadastrou o carro agora (voltou da tela de carro)? Já deixa ele escolhido.
    if (!_editing && vehicles.isNotEmpty && !vehicles.any((v) => v.id == _vehicleId)) {
      _vehicleId = vehicles.first.id;
      _seats = vehicles.first.seats;
    }
    final maxSeats = vehicles.where((v) => v.id == _vehicleId).firstOrNull?.seats ?? 6;
    if (_seats > maxSeats) _seats = maxSeats;

    return StepScaffold(
      title: _editing ? 'Editar viagem' : (_forEvent ? (_ida ? 'Carona de ida' : 'Carona de volta') : 'Oferecer carona'),
      subtitle: _editing
          ? 'O trajeto continua o mesmo. Ajuste horário, vagas e repetição.'
          : _forEvent
              ? (_event == null
                  ? 'Carregando o evento…'
                  : (_ida ? 'Para ${_event!.name}. Diga de onde você sai.' : 'Saindo de ${_event!.name}. Diga para onde você vai.'))
              : 'Diga por onde você já vai passar. O Bora encontra as paradas no caminho e quem precisa de carona nelas.',
      action: BoraButton(
        label: _editing ? 'Salvar' : 'Publicar viagem',
        loading: _loading,
        onPressed: _editing || (_plan != null && !_routing) ? _submit : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_editing) ...[
            BoraCard(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
              child: Column(
                children: [
                  _PlaceRow(
                      label: 'Saída',
                      value: _origin?.label,
                      dot: true,
                      locked: _forEvent && !_ida,
                      onTap: () => _pick(origin: true)),
                  const Divider(height: 1),
                  _PlaceRow(
                      label: 'Destino',
                      value: _destination?.label,
                      locked: _forEvent && _ida,
                      onTap: () => _pick(origin: false)),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            if (_routing)
              const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
            else if (_plan != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.lg - 4),
                child: SizedBox(
                  height: 190,
                  child: BoraMap(
                    interactive: false,
                    fitPoints: _plan!.points,
                    lines: [routeLine('plan', _plan!.points)],
                    pins: [originPin(_plan!.points.first), destinationPin(_plan!.points.last)],
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(child: Metric(value: formatKm(_plan!.distanceM), label: 'distância')),
                  Expanded(child: Metric(value: '${_plan!.duration.inMinutes} min', label: 'sem trânsito')),
                  Expanded(
                    child: Metric(value: '${_demand ?? '–'}', label: _forEvent ? 'pedindo carona' : 'buscas no caminho', alignEnd: true),
                  ),
                ],
              ),
              if ((_demand ?? 0) > 0) ...[
                const SizedBox(height: Space.sm),
                Pill('$_demand ${_demand == 1 ? 'pessoa procurou' : 'pessoas procuraram'} carona nesse trajeto', icon: Icons.trending_up),
              ],
            ],
            const SectionHeader('Detalhes', padding: EdgeInsets.only(top: Space.lg, bottom: Space.xs)),
          ],
          if (vehicles.isEmpty)
            BoraCard(
              onTap: () => context.push('/vehicle'),
              child: const Row(children: [
                IconTile(Icons.directions_car_outlined),
                SizedBox(width: Space.sm),
                Expanded(child: Text('Cadastrar um carro', style: AppText.bodyStrong)),
                Icon(Icons.chevron_right, color: AppColors.textFaint),
              ]),
            )
          else
            DropdownButtonFormField<String>(
              value: _vehicleId,
              decoration: const InputDecoration(labelText: 'Carro', prefixIcon: Icon(Icons.directions_car_outlined)),
              dropdownColor: AppColors.surfaceRaised,
              items: [for (final v in vehicles) DropdownMenuItem(value: v.id, child: Text('${v.label} · ${v.plate}'))],
              onChanged: _editing
                  ? null
                  : (v) => setState(() {
                        _vehicleId = v;
                        _seats = vehicles.firstWhere((x) => x.id == v).seats;
                      }),
            ),
          const SizedBox(height: Space.sm),
          BoraCard(
            onTap: _pickDeparture,
            child: Row(children: [
              const IconTile(Icons.schedule),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Saída', style: AppText.caption),
                  Text(formatWhen(_departure), style: AppText.bodyStrong),
                ]),
              ),
              const Icon(Icons.edit_outlined, size: 18, color: AppColors.textFaint),
            ]),
          ),
          const SizedBox(height: Space.sm),
          BoraCard(
            child: Row(children: [
              const IconTile(Icons.event_seat_outlined),
              const SizedBox(width: Space.sm),
              const Expanded(child: Text('Vagas', style: AppText.bodyStrong)),
              IconButton(onPressed: _seats > 1 ? () => setState(() => _seats--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$_seats', style: AppText.number),
              IconButton(onPressed: _seats < maxSeats ? () => setState(() => _seats++) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
          ),
          const SectionHeader('Repetir', padding: EdgeInsets.only(top: Space.lg, bottom: Space.xs)),
          Wrap(
            spacing: Space.xs,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(weekdayShort(d)),
                  selected: _weekdays.contains(d),
                  onSelected: (on) => setState(() => on ? _weekdays.add(d) : _weekdays.remove(d)),
                ),
            ],
          ),
          if (!_editing) ...[
            if (communities.isNotEmpty) ...[
              const SectionHeader('Quem pode ver', padding: EdgeInsets.only(top: Space.lg, bottom: Space.xs)),
              Text(_communityIds.isEmpty ? 'Todos os usuários verificados' : 'Só as comunidades marcadas', style: AppText.caption),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final c in communities)
                    FilterChip(
                      label: Text(c.name),
                      selected: _communityIds.contains(c.id),
                      onSelected: (on) => setState(() => on ? _communityIds.add(c.id) : _communityIds.remove(c.id)),
                    ),
                ],
              ),
            ],
            if (me.gender == Gender.female) ...[
              const SizedBox(height: Space.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _womenOnly,
                onChanged: (v) => setState(() => _womenOnly = v),
                title: const Text('Só mulheres', style: AppText.bodyStrong),
                subtitle: const Text('Apenas passageiras poderão reservar.', style: AppText.caption),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.label, required this.value, required this.onTap, this.dot = false, this.locked = false});
  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool dot;
  final bool locked;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: locked ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: dot ? AppColors.text : AppColors.green, shape: dot ? BoxShape.circle : BoxShape.rectangle),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.caption),
                    Text(value ?? 'Escolher', style: value == null ? AppText.body : AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(locked ? Icons.event : Icons.chevron_right, color: AppColors.textFaint),
            ],
          ),
        ),
      );
}
