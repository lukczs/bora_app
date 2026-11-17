import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../core/widgets/cards.dart';
import '../../data/bora_store.dart';
import '../../domain/models.dart';

class TripsTab extends ConsumerWidget {
  const TripsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    return PageScaffold(
      title: 'Viagens',
      onRefresh: store.refreshTrips,
      children: [
        const SectionHeader('Minhas reservas'),
        if (store.myBookings.isEmpty)
          const EmptyState(
            icon: Icons.confirmation_number_outlined,
            title: 'Nenhuma reserva ainda',
            text: 'No Início, toque em "Para onde vamos?" para ver quem passa perto de você.',
          ),
        for (final b in store.myBookings)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xs),
            child: _BookingCard(booking: b, store: store),
          ),
        const SectionHeader('Viagens que eu ofereço'),
        if (store.myRides.isEmpty)
          const EmptyState(
            icon: Icons.directions_car_outlined,
            title: 'Nenhuma viagem publicada',
            text: 'No Início, toque em "Oferecer carona" e diga por onde você já vai passar.',
          ),
        for (final r in store.myRides)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xs),
            child: _RideCard(ride: r, store: store),
          ),
      ],
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
                    style: AppText.subtitle),
              ),
              Pill(text, color: color),
            ],
          ),
          const SizedBox(height: Space.sm),
          RouteSummary(from: store.stop(booking.pickupStopId).name, to: store.stop(booking.dropoffStopId).name),
          const SizedBox(height: 10),
          Text('${ride == null ? '' : 'Com ${ride.driver.firstName} · '}${formatCents(booking.priceCents)}', style: AppText.caption),
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
                    style: AppText.subtitle),
              ),
              Pill(text, color: color),
            ],
          ),
          if (ride.recurringDays.isNotEmpty) Text(formatRecurring(ride.recurringDays), style: AppText.caption),
          const SizedBox(height: Space.sm),
          RouteSummary(
            from: ride.originLabel ?? store.stop(ride.originStopId).name,
            to: ride.destLabel ?? store.stop(ride.destinationStopId).name,
          ),
        ],
      ),
    );
  }
}
