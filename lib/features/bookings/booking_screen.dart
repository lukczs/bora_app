import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/bora_map.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.bookingId});
  final String bookingId;
  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  bool _loading = false;

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cancelar reserva?'),
        content: const Text('A vaga volta a ficar disponível para outra pessoa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Manter reserva')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Cancelar reserva', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await ref.read(storeProvider).cancelBooking(widget.bookingId);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final booking = store.myBooking(widget.bookingId);
    final ride = booking?.ride;
    if (booking == null || ride == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Reserva não encontrada.')));
    }
    final pickup = store.stop(booking.pickupStopId);
    final dropoff = store.stop(booking.dropoffStopId);
    final from = ride.path.indexOf(pickup.id);
    final to = ride.path.indexOf(dropoff.id);
    final stretch = store.graph.pointsOf(ride.path.sublist(from < 0 ? 0 : from, to < 0 ? ride.path.length : to + 1));
    final rideCancelled = ride.status == RideStatus.cancelled;

    return Scaffold(
      appBar: AppBar(title: const Text('Minha reserva')),
      body: RefreshIndicator(
        color: AppColors.green,
        onRefresh: store.refreshTrips,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            if (booking.status == BookingStatus.cancelled)
              Pill(rideCancelled ? 'O motorista cancelou esta viagem' : 'Reserva cancelada',
                  icon: Icons.cancel, color: AppColors.danger)
            else ...[
              const Text('Mostre este código ao motorista na hora de embarcar'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x1F22C55E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.green),
                ),
                child: Text(booking.boardingCode ?? '----',
                    style: const TextStyle(
                        color: AppColors.mint, fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: 16)),
              ),
            ],
            const SizedBox(height: 22),
            Text(formatWhen(ride.departureAt), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            RouteSummary(from: pickup.name, to: dropoff.name),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 190,
                child: BoraMap(
                  interactive: false,
                  fitPoints: stretch,
                  polylines: [boraRouteLine(stretch)],
                  markers: [
                    stopMarker(pickup.point, highlight: true, label: 'Embarque'),
                    stopMarker(dropoff.point, highlight: true, label: 'Destino'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            BoraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Motorista: ${ride.driver.fullName}',
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('${ride.vehicle.label}, placa ${ride.vehicle.plate}'),
                  const SizedBox(height: 6),
                  const Text('Confira a placa antes de entrar no carro.'),
                  const Divider(height: 28, color: AppColors.line),
                  Row(
                    children: [
                      const Expanded(child: Text('Valor combinado (pague direto ao motorista)')),
                      Text(formatCents(booking.priceCents),
                          style: const TextStyle(color: AppColors.green, fontSize: 18, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (booking.status == BookingStatus.reserved)
              BoraButton(label: 'Cancelar reserva', secondary: true, loading: _loading, onPressed: _cancel),
          ],
        ),
      ),
    );
  }
}
