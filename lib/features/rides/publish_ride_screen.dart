import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';

/// Publicar viagem. Com [editRideId], vira edição (horário, vagas e recorrência).
class PublishRideScreen extends ConsumerStatefulWidget {
  const PublishRideScreen({super.key, this.editRideId});
  final String? editRideId;
  @override
  ConsumerState<PublishRideScreen> createState() => _PublishRideScreenState();
}

class _PublishRideScreenState extends ConsumerState<PublishRideScreen> {
  String? _origin;
  String? _destination;
  String? _vehicleId;
  int _seats = 1;
  late DateTime _departure;
  final Set<int> _weekdays = {};
  final Set<String> _communityIds = {};
  bool _womenOnly = false;
  bool _loading = false;

  bool get _editing => widget.editRideId != null;

  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider);
    final myVehicles = store.myVehicles;
    final ride = _editing ? store.myRide(widget.editRideId!) : null;

    if (ride != null) {
      _origin = ride.originStopId;
      _destination = ride.destinationStopId;
      _vehicleId = ride.vehicle.id;
      _seats = ride.seatsTotal;
      _departure = ride.departureAt;
      _weekdays.addAll(ride.recurringDays);
      _communityIds.addAll(ride.communityIds);
      _womenOnly = ride.womenOnly;
    } else {
      _origin = store.graph.nearestBoardable(store.position).id;
      _vehicleId = myVehicles.isEmpty ? null : myVehicles.first.id;
      _seats = myVehicles.isEmpty ? 1 : myVehicles.first.seats;
      final soon = DateTime.now().add(const Duration(minutes: 30));
      _departure = DateTime(soon.year, soon.month, soon.day, soon.hour, (soon.minute ~/ 5) * 5);
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

  Future<void> _save() async {
    if (_origin == null || _destination == null || _vehicleId == null) {
      showBoraError(context, 'Escolha de onde sai, para onde vai e qual carro.');
      return;
    }
    final store = ref.read(storeProvider);
    final path = store.graph.shortestPath(_origin!, _destination!);
    if (path == null) {
      showBoraError(context, 'Ainda não conhecemos um trajeto entre essas duas paradas.');
      return;
    }
    setState(() => _loading = true);
    try {
      if (_editing) {
        await store.updateRide(widget.editRideId!,
            departureAt: _departure, seats: _seats, recurringDays: _weekdays.toList());
        if (mounted) context.pop();
      } else {
        final rideId = await store.publishRide(
          vehicleId: _vehicleId!,
          path: path,
          departureAt: _departure,
          seats: _seats,
          recurringDays: _weekdays.toList(),
          womenOnly: _womenOnly,
          communityIds: _communityIds.toList(),
        );
        if (mounted) context.pushReplacement('/my-ride/$rideId');
      }
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
    final graph = store.graph;
    final myVehicles = store.myVehicles;
    final myCommunities = store.myCommunities.where((c) => c.myStatus == MemberStatus.active).toList();
    final stopItems = [
      for (final s in graph.boardable)
        DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
    ];

    final path = (_origin != null && _destination != null)
        ? graph.shortestPath(_origin!, _destination!)
        : null;
    final boardableOnPath = path?.where((id) => store.stop(id).boardable).toList() ?? const <String>[];
    final maxSeats = myVehicles.where((v) => v.id == _vehicleId).firstOrNull?.seats ?? 6;
    if (_seats > maxSeats) _seats = maxSeats;

    const label = TextStyle(color: AppColors.text, fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar viagem' : 'Publicar viagem')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          DropdownButtonFormField<String>(
            value: _origin,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'De onde você sai'),
            items: stopItems,
            onChanged: _editing ? null : (v) => setState(() => _origin = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _destination,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Para onde você vai'),
            items: stopItems,
            onChanged: _editing ? null : (v) => setState(() => _destination = v),
          ),
          const SizedBox(height: 16),
          if (path != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 200,
                child: BoraMap(
                  key: ValueKey('$_origin>$_destination'),
                  interactive: false,
                  fitPoints: graph.pointsOf(path),
                  polylines: [boraRouteLine(graph.pointsOf(path))],
                  markers: [for (final id in boardableOnPath) stopMarker(store.stop(id).point)],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
                'Rota de ${formatKm(graph.distanceAlong(path, 0, path.length - 1))} passando por ${boardableOnPath.length} paradas. '
                'Quem embarcar em qualquer uma delas pode pegar carona com você.'),
          ] else if (_origin != null && _destination != null)
            const Text('Ainda não conhecemos um trajeto entre essas duas paradas.',
                style: TextStyle(color: AppColors.warning)),
          const SizedBox(height: 22),
          if (!_editing) ...[
            DropdownButtonFormField<String>(
              value: _vehicleId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Carro'),
              items: [
                for (final v in myVehicles)
                  DropdownMenuItem(value: v.id, child: Text('${v.label} (${v.plate})')),
              ],
              onChanged: (v) => setState(() {
                _vehicleId = v;
                _seats = myVehicles.firstWhere((x) => x.id == v).seats;
              }),
            ),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              const Expanded(child: Text('Vagas oferecidas', style: label)),
              IconButton(
                onPressed: _seats > 1 ? () => setState(() => _seats--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_seats',
                  style: const TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: _seats < maxSeats ? () => setState(() => _seats++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const Divider(color: AppColors.line, height: 28),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Saída', style: label),
            subtitle: Text(formatWhen(_departure)),
            trailing: const Icon(Icons.edit_calendar, color: AppColors.green),
            onTap: _pickDeparture,
          ),
          const SizedBox(height: 6),
          const Text('Repetir toda semana', style: label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(weekdayShort(d)),
                  selected: _weekdays.contains(d),
                  showCheckmark: false,
                  selectedColor: const Color(0x3322C55E),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: _weekdays.contains(d) ? AppColors.green : AppColors.line),
                  onSelected: (on) => setState(() => on ? _weekdays.add(d) : _weekdays.remove(d)),
                ),
            ],
          ),
          if (!_editing) ...[
            const Divider(color: AppColors.line, height: 36),
            const Text('Quem pode ver esta viagem', style: label),
            const SizedBox(height: 4),
            Text(_communityIds.isEmpty
                ? 'Todas as pessoas verificadas do Bora.'
                : 'Só membros das comunidades marcadas.'),
            const SizedBox(height: 8),
            if (myCommunities.isEmpty)
              const Text('Você ainda não participa de nenhuma comunidade.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in myCommunities)
                    FilterChip(
                      label: Text(c.name),
                      avatar: const Icon(Icons.groups, size: 16),
                      selected: _communityIds.contains(c.id),
                      showCheckmark: false,
                      selectedColor: const Color(0x3322C55E),
                      backgroundColor: AppColors.surface,
                      side: BorderSide(
                          color: _communityIds.contains(c.id) ? AppColors.green : AppColors.line),
                      onSelected: (on) =>
                          setState(() => on ? _communityIds.add(c.id) : _communityIds.remove(c.id)),
                    ),
                ],
              ),
            if (me.gender == Gender.female) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _womenOnly,
                onChanged: (v) => setState(() => _womenOnly = v),
                title: const Text('Apenas mulheres', style: label),
                subtitle: const Text('Só passageiras mulheres poderão ver e reservar esta viagem.'),
              ),
            ],
          ],
          const SizedBox(height: 24),
          BoraButton(
            label: _editing ? 'Salvar alterações' : 'Publicar viagem',
            loading: _loading,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
