import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cards.dart';
import '../../data/bora_store.dart';
import '../../domain/models.dart';

class TripsTab extends ConsumerWidget {
  const TripsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.green,
        onRefresh: store.refreshTrips,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Text('Viagens', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            const Text('Puxe para baixo para atualizar.'),
            const SizedBox(height: 22),
            Text('Minhas reservas', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (store.myBookings.isEmpty)
              const EmptyState(
                icon: Icons.confirmation_number_outlined,
                title: 'Você ainda não reservou nenhuma carona',
                text: 'Na aba Início, toque em "Buscar carona" para ver quem passa perto de você.',
              ),
            for (final b in store.myBookings) ...[
              _BookingCard(booking: b, store: store),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 22),
            Text('Viagens que eu ofereço', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (store.myRides.isEmpty)
              const EmptyState(
                icon: Icons.directions_car_outlined,
                title: 'Você ainda não publicou viagens',
                text: 'Na aba Início, mude para "Vou dirigir" e publique o seu trajeto.',
              ),
            for (final r in store.myRides) ...[
              _RideCard(ride: r, store: store),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.store});
  final Booking booking;
  final BoraStore store;

  @override
  Widget build(BuildContext context) {
    final ride = booking.ride;
    final (text, color) = switch (booking.status) {
      BookingStatus.reserved => ('Reservada', AppColors.green),
      BookingStatus.boarded => ('Em viagem', AppColors.warning),
      BookingStatus.completed => ('Concluída', AppColors.textMuted),
      BookingStatus.cancelled => ('Cancelada', AppColors.danger),
    };

    return BoraCard(
      onTap: () => context.push('/booking/${booking.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ride == null ? 'Reserva' : formatWhen(ride.departureAt),
                    style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Pill(text, color: color),
            ],
          ),
          const SizedBox(height: 12),
          RouteSummary(from: store.stop(booking.pickupStopId).name, to: store.stop(booking.dropoffStopId).name),
          const SizedBox(height: 10),
          Text('${ride == null ? '' : 'Com ${ride.driver.firstName}, '}${formatCents(booking.priceCents)}'),
        ],
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride, required this.store});
  final Ride ride;
  final BoraStore store;

  @override
  Widget build(BuildContext context) {
    final taken = ride.seatsTotal - ride.seatsAvailable;
    final (text, color) = switch (ride.status) {
      RideStatus.open => ('$taken de ${ride.seatsTotal} vagas', AppColors.green),
      RideStatus.inProgress => ('Em andamento', AppColors.warning),
      RideStatus.completed => ('Concluída', AppColors.textMuted),
      RideStatus.cancelled => ('Cancelada', AppColors.danger),
    };

    return BoraCard(
      onTap: () => context.push('/my-ride/${ride.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(formatWhen(ride.departureAt),
                    style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Pill(text, color: color),
            ],
          ),
          if (ride.recurringDays.isNotEmpty) Text(formatRecurring(ride.recurringDays)),
          const SizedBox(height: 12),
          RouteSummary(from: store.stop(ride.originStopId).name, to: store.stop(ride.destinationStopId).name),
        ],
      ),
    );
  }
}
