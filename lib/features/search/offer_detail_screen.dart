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
import '../../data/errors.dart';

class OfferDetailScreen extends ConsumerStatefulWidget {
  const OfferDetailScreen({super.key, required this.rideId});
  final String rideId;
  @override
  ConsumerState<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends ConsumerState<OfferDetailScreen> {
  bool _loading = false;

  Future<void> _book() async {
    final offer = ref.read(storeProvider).offer(widget.rideId)!;
    setState(() => _loading = true);
    try {
      final bookingId = await ref.read(storeProvider).bookSeat(
            rideId: widget.rideId,
            pickupStopId: offer.pickupStopId,
            dropoffStopId: offer.dropoffStopId,
          );
      if (mounted) context.pushReplacement('/booking/$bookingId');
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final offer = store.offer(widget.rideId);
    if (offer == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Esta oferta expirou. Volte e busque de novo.')),
      );
    }
    final ride = offer.ride;
    final pickup = store.stop(offer.pickupStopId);
    final dropoff = store.stop(offer.dropoffStopId);
    final from = ride.path.indexOf(pickup.id);
    final to = ride.path.indexOf(dropoff.id);
    final myStretch = store.graph.pointsOf(ride.path.sublist(from < 0 ? 0 : from, to < 0 ? ride.path.length : to + 1));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes da carona')),
      body: Column(
        children: [
          SizedBox(
            height: 230,
            child: BoraMap(
              fitPoints: myStretch,
              polylines: [boraRouteLine(store.graph.pointsOf(ride.path), faint: true), boraRouteLine(myStretch)],
              markers: [
                stopMarker(pickup.point, highlight: true, label: 'Embarque'),
                stopMarker(dropoff.point, highlight: true, label: 'Destino'),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(formatWhen(ride.departureAt), style: Theme.of(context).textTheme.titleLarge)),
                    Text(formatCents(offer.priceCents),
                        style: const TextStyle(color: AppColors.green, fontSize: 24, fontWeight: FontWeight.w800)),
                  ],
                ),
                if (ride.recurringDays.isNotEmpty) Text(formatRecurring(ride.recurringDays)),
                const SizedBox(height: 18),
                RouteSummary(from: pickup.name, to: dropoff.name),
                const SizedBox(height: 8),
                Text('${formatKm(offer.distanceM)} no seu trecho. O valor é o rateio de custo, pago direto ao motorista.'),
                const SizedBox(height: 20),
                BoraCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: const Color(0x3322C55E),
                            child: Text(ride.driver.initial,
                                style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ride.driver.fullName,
                                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                                Text(ride.driver.ratingLabel),
                              ],
                            ),
                          ),
                          const Pill('Verificado', icon: Icons.verified_user),
                        ],
                      ),
                      const Divider(height: 28, color: AppColors.line),
                      Row(
                        children: [
                          const Icon(Icons.directions_car, color: AppColors.textMuted),
                          const SizedBox(width: 10),
                          Expanded(child: Text(ride.vehicle.label, style: const TextStyle(color: AppColors.text))),
                          Text(ride.vehicle.plate,
                              style: const TextStyle(
                                  color: AppColors.text, fontWeight: FontWeight.w800, letterSpacing: 1)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (offer.sharedCommunities.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Vocês têm em comum',
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final c in offer.sharedCommunities) Pill(c, icon: Icons.groups)],
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: BoraButton(label: 'Reservar minha vaga', loading: _loading, onPressed: _book),
            ),
          ),
        ],
      ),
    );
  }
}
