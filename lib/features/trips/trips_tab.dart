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
import '../ratings/rating_sheet.dart';

/// Viagens: próximas, histórico e canceladas — como passageiro e como motorista.
class TripsTab extends ConsumerStatefulWidget {
  const TripsTab({super.key});
  @override
  ConsumerState<TripsTab> createState() => _TripsTabState();
}

enum _View { upcoming, history, cancelled }

/// Uma linha da lista: reserva (passageiro) ou viagem (motorista).
class _Item {
  _Item.booking(Booking this.booking) : ride = null, when = booking.ride?.departureAt ?? DateTime(2000);
  _Item.ride(Ride this.ride) : booking = null, when = ride.departureAt;
  final Booking? booking;
  final Ride? ride;
  final DateTime when;
}

class _TripsTabState extends ConsumerState<TripsTab> {
  _View _view = _View.upcoming;

  /// Viagem que passou da hora há muito tempo e nunca começou vai para o histórico.
  static bool _expired(Ride r) =>
      r.status == RideStatus.open && r.departureAt.isBefore(DateTime.now().subtract(const Duration(hours: 6)));

  _View _viewOf(_Item i) {
    final b = i.booking, r = i.ride;
    if (b != null) {
      return switch (b.status) {
        BookingStatus.reserved || BookingStatus.boarded => _View.upcoming,
        BookingStatus.completed => _View.history,
        BookingStatus.cancelled => _View.cancelled,
      };
    }
    return switch (r!.status) {
      RideStatus.cancelled => _View.cancelled,
      RideStatus.completed => _View.history,
      _ => _expired(r) ? _View.history : _View.upcoming,
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final all = [
      for (final b in store.myBookings) _Item.booking(b),
      for (final r in store.myRides) _Item.ride(r),
    ];
    final counts = {for (final v in _View.values) v: all.where((i) => _viewOf(i) == v).length};
    final items = all.where((i) => _viewOf(i) == _view).toList()
      ..sort((a, b) => _view == _View.upcoming ? a.when.compareTo(b.when) : b.when.compareTo(a.when));

    // Resumo do histórico
    final doneRides = all.where((i) => _viewOf(i) == _View.history && i.ride?.status == RideStatus.completed).length;
    final doneBookings = all.where((i) => i.booking?.status == BookingStatus.completed).length;
    final km = all
            .where((i) => _viewOf(i) == _View.history)
            .fold<int>(0, (sum, i) => sum + (i.booking?.distanceM ?? (i.ride?.status == RideStatus.completed ? i.ride!.distanceM : 0))) /
        1000;

    return PageScaffold(
      title: 'Viagens',
      onRefresh: store.refreshTrips,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
          child: SegmentedButton<_View>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _View.upcoming, label: Text('Próximas${_n(counts[_View.upcoming]!)}')),
              ButtonSegment(value: _View.history, label: Text('Histórico${_n(counts[_View.history]!)}')),
              ButtonSegment(value: _View.cancelled, label: Text('Canceladas${_n(counts[_View.cancelled]!)}')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
        ),
        if (store.pendingRatings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
            child: BoraCard(
              onTap: () {
                store.skippedRatings.clear();
                askPendingRatings(context, ref);
              },
              child: Row(children: [
                const Icon(Icons.star_rounded, color: AppColors.warning),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                      store.pendingRatings.length == 1
                          ? 'Falta avaliar 1 viagem'
                          : 'Faltam avaliar ${store.pendingRatings.length} viagens',
                      style: AppText.bodyStrong),
                ),
                const Text('Avaliar', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        if (_view == _View.history && (doneRides + doneBookings) > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
            child: Row(children: [
              Expanded(child: Metric(value: '$doneRides', label: 'dirigindo')),
              Expanded(child: Metric(value: '$doneBookings', label: 'de carona')),
              Expanded(child: Metric(value: km.toStringAsFixed(km < 10 ? 1 : 0).replaceAll('.', ','), label: 'km rodados')),
            ]),
          ),
        if (items.isEmpty)
          switch (_view) {
            _View.upcoming => const EmptyState(
                icon: Icons.route_outlined,
                title: 'Nada marcado',
                text: 'No Início, toque em "Para onde vamos?" para pegar carona ou em "Oferecer carona" para levar alguém.',
              ),
            _View.history => const EmptyState(
                icon: Icons.history,
                title: 'Sem viagens concluídas ainda',
                text: 'As viagens que você fizer, dirigindo ou de carona, ficam guardadas aqui.',
              ),
            _View.cancelled => const EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'Nenhuma cancelada',
                text: 'Reservas e viagens canceladas aparecem aqui, com o motivo.',
              ),
          },
        for (final i in items)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xs),
            child: i.booking != null
                ? _BookingCard(booking: i.booking!, store: store)
                : _RideCard(ride: i.ride!, store: store, expired: _expired(i.ride!)),
          ),
      ],
    );
  }

  static String _n(int n) => n == 0 ? '' : ' ($n)';
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
      BookingStatus.cancelled => (switch (booking.cancelledBy) {
          'no_show' => 'Não embarcou',
          'driver' => 'Removido',
          'ride' => 'Viagem cancelada',
          _ => 'Cancelada por você',
        }, AppColors.danger),
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
          Text('De carona${ride == null ? '' : ' com ${ride.driver.firstName}'} · ${formatCents(booking.priceCents)}', style: AppText.caption),
        ],
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride, required this.store, this.expired = false});
  final Ride ride;
  final BoraStore store;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final taken = ride.seatsTotal - ride.seatsAvailable;
    final carried = ride.bookings.where((b) => b.status == BookingStatus.completed).length;
    final (text, color) = switch (ride.status) {
      RideStatus.open when expired => ('Não iniciada', AppColors.textMuted),
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
          const SizedBox(height: 10),
          Text('Você dirige · ${(ride.distanceM / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
              '${ride.status == RideStatus.completed ? ' · $carried passageiro${carried == 1 ? '' : 's'}' : ''}',
              style: AppText.caption),
        ],
      ),
    );
  }
}
