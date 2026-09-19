import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
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
                child: BoraMap(
                  fitPoints: points,
                  polylines: [boraRouteLine(points)],
                  markers: [
                    for (final id in ride.path.where((id) => store.stop(id).boardable))
                      stopMarker(store.stop(id).point),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text(formatWhen(ride.departureAt), style: Theme.of(context).textTheme.titleLarge)),
                if (ride.status == RideStatus.cancelled)
                  const Pill('Cancelada', icon: Icons.cancel, color: AppColors.danger)
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
              Text(formatCents(booking.priceCents),
                  style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w800)),
            ],
          ),
          if (p != null) Text(p.ratingLabel),
          const SizedBox(height: 10),
          Text('Embarca em ${store.stop(booking.pickupStopId).name}', style: const TextStyle(color: AppColors.text)),
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
