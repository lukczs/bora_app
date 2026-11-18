import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
import 'ride_route_map.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/bora_store.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';

/// A viagem do ponto de vista do motorista: rota, passageiros, editar e cancelar.
class DriverRideScreen extends ConsumerStatefulWidget {
  const DriverRideScreen({super.key, required this.rideId});
  final String rideId;
  @override
  ConsumerState<DriverRideScreen> createState() => _DriverRideScreenState();
}

class _DriverRideScreenState extends ConsumerState<DriverRideScreen> {
  bool _loading = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    // Carrega todas as paradas do caminho para aparecerem no mapinha.
    final ride = ref.read(storeProvider).myRide(widget.rideId);
    if (ride != null) {
      ref.read(storeProvider).ensureStops(ride.path).then((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    }
  }

  /// Inicia a corrida e abre a navegação.
  Future<void> _startRide(Ride ride) async {
    setState(() => _starting = true);
    try {
      if (ride.status == RideStatus.open) await ref.read(storeProvider).startRide(ride.id);
      if (mounted) await context.push('/navigate/${ride.id}');
      if (mounted) await ref.read(storeProvider).refreshTrips();
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _cancel(int passengers) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cancelar viagem?'),
        content: Text(passengers == 0
            ? 'A viagem deixa de aparecer nas buscas.'
            : 'As reservas desta viagem ($passengers) serão canceladas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Manter viagem')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Cancelar viagem', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).cancelRide(widget.rideId);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final ride = store.myRide(widget.rideId);
    if (ride == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Viagem não encontrada.')));
    }
    final points = store.graph.pointsOf(ride.path);
    final open = ride.status == RideStatus.open;
    final running = ride.status == RideStatus.inProgress;
    final startsAt = ride.departureAt.subtract(const Duration(minutes: 60));
    final canStart = open && DateTime.now().isAfter(startsAt);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha viagem'),
        actions: [
          if (open)
            IconButton(
              tooltip: 'Editar viagem',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/publish?edit=${ride.id}'),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.green,
        onRefresh: store.refreshTrips,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 210,
                child: RideRouteMap(
                  rideId: ride.id,
                  fallback: points,
                  markers: [
                    for (final id in ride.path.where((id) => store.stop(id).boardable))
                      stopPin(id, store.stop(id).point),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (running || canStart) ...[
              BoraButton(
                label: running ? 'Abrir navegação' : 'Iniciar corrida',
                icon: Icons.navigation,
                loading: _starting,
                onPressed: () => _startRide(ride),
              ),
              const SizedBox(height: 6),
              Text(
                running
                    ? 'Corrida em andamento. A rota passa por quem ainda falta pegar ou deixar.'
                    : 'O app vira navegação com a rota até cada passageiro.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
            ] else if (open) ...[
              Text('Dá para iniciar a corrida a partir de ${formatTime(startsAt)} (1 hora antes da saída).',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 18),
            ],
            Row(
              children: [
                Expanded(child: Text(formatWhen(ride.departureAt), style: Theme.of(context).textTheme.titleLarge)),
                if (ride.status == RideStatus.cancelled)
                  const Pill('Cancelada', icon: Icons.cancel, color: AppColors.danger)
                else if (ride.status == RideStatus.completed)
                  const Pill('Concluída', icon: Icons.check_circle, color: AppColors.textMuted)
                else if (running)
                  const Pill('Em andamento', icon: Icons.navigation, color: AppColors.warning)
                else
                  Pill('${ride.seatsTotal - ride.seatsAvailable} de ${ride.seatsTotal} vagas', icon: Icons.event_seat),
              ],
            ),
            if (ride.recurringDays.isNotEmpty) Text(formatRecurring(ride.recurringDays)),
            const SizedBox(height: 14),
            RouteSummary(from: store.stop(ride.originStopId).name, to: store.stop(ride.destinationStopId).name),
            const SizedBox(height: 12),
            Text('${ride.vehicle.label}, placa ${ride.vehicle.plate}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (ride.visibility == RideVisibility.public)
                  const Pill('Aberta a todos os verificados', icon: Icons.public)
                else
                  for (final name in ride.communityNames) Pill(name, icon: Icons.groups),
                if (ride.womenOnly) const Pill('Só mulheres', icon: Icons.female, color: Color(0xFFF0ABFC)),
              ],
            ),
            const SizedBox(height: 26),
            Text('Passageiros', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (ride.bookings.isEmpty)
              const EmptyState(
                icon: Icons.event_seat_outlined,
                title: 'Ninguém reservou ainda',
                text: 'As vagas são preenchidas automaticamente. Puxe a tela para baixo para atualizar.',
              )
            else
              for (final b in ride.bookings) ...[
                _PassengerCard(booking: b, store: store),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 18),
            if (open)
              BoraButton(
                label: 'Cancelar viagem',
                secondary: true,
                loading: _loading,
                onPressed: () => _cancel(ride.bookings.length),
              ),
          ],
        ),
      ),
    );
  }
}

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({required this.booking, required this.store});
  final Booking booking;
  final BoraStore store;

  @override
  Widget build(BuildContext context) {
    final p = booking.passenger;
    return BoraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p?.fullName ?? 'Passageiro',
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
              ),
              if (booking.status == BookingStatus.boarded)
                const Padding(padding: EdgeInsets.only(right: 8), child: Pill('No carro', icon: Icons.airline_seat_recline_normal, color: AppColors.warning))
              else if (booking.status == BookingStatus.completed)
                const Padding(padding: EdgeInsets.only(right: 8), child: Pill('Desceu', icon: Icons.check, color: AppColors.textMuted)),
              Text(formatCents(booking.priceCents),
                  style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
            ],
          ),
          if (p != null) Text(p.ratingLabel),
          const SizedBox(height: 10),
          Row(children: [
            Icon(booking.pickupByCar ? Icons.directions_walk : Icons.directions_bus_outlined, size: 18, color: AppColors.green),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                booking.pickupByCar
                    ? 'Vem a pé até o carro na saída${booking.pickupEta == null ? '' : ' · ${formatTime(booking.pickupEta!)}'}'
                    : 'Pegar em ${booking.pickupName ?? store.stop(booking.pickupStopId).name}'
                        '${booking.pickupEta == null ? '' : ' às ${formatTime(booking.pickupEta!)}'}',
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          Text('Desce em ${store.stop(booking.dropoffStopId).name}'),
          if (booking.sharedCommunities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final c in booking.sharedCommunities) Pill(c, icon: Icons.groups)],
            ),
          ],
        ],
      ),
    );
  }
}
