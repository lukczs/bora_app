import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/bora_button.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/step_scaffold.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialPickupStopId});
  final String? initialPickupStopId;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String? _pickup;
  String? _dropoff;
  bool _onlyCommunities = false;
  bool _loading = false;
  List<RideOffer>? _offers;

  @override
  void initState() {
    super.initState();
    final graph = ref.read(storeProvider).graph;
    final initial = widget.initialPickupStopId;
    _pickup = (initial != null && graph.stops[initial]?.boardable == true) ? initial : null;
  }

  Future<void> _search() async {
    if (_pickup == null || _dropoff == null) {
      showBoraError(context, 'Escolha onde você embarca e onde desce.');
      return;
    }
    if (_pickup == _dropoff) {
      showBoraError(context, 'Embarque e destino precisam ser paradas diferentes.');
      return;
    }
    setState(() => _loading = true);
    try {
      final offers = await ref.read(storeProvider).searchRides(
            pickupStopId: _pickup!,
            dropoffStopId: _dropoff!,
            onlyMyCommunities: _onlyCommunities,
          );
      if (mounted) setState(() => _offers = offers);
    } catch (e) {
      if (mounted) showBoraError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final items = [
      for (final s in store.graph.boardable)
        DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Buscar carona')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          DropdownButtonFormField<String>(
            value: _pickup,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Onde você embarca', prefixIcon: Icon(Icons.radio_button_checked, size: 18)),
            items: items,
            onChanged: (v) => setState(() {
              _pickup = v;
              _offers = null;
            }),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _dropoff,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Para onde você vai', prefixIcon: Icon(Icons.location_on, size: 20)),
            items: items,
            onChanged: (v) => setState(() {
              _dropoff = v;
              _offers = null;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _onlyCommunities,
            onChanged: (v) => setState(() {
              _onlyCommunities = v;
              _offers = null;
            }),
            title: const Text('Só pessoas das minhas comunidades',
                style: TextStyle(color: AppColors.text, fontSize: 15)),
          ),
          const SizedBox(height: 8),
          BoraButton(label: 'Buscar carona', loading: _loading, onPressed: _search),
          const SizedBox(height: 28),
          if (_offers != null && _offers!.isEmpty)
            const EmptyState(
              icon: Icons.search_off,
              title: 'Nenhuma carona nesse trajeto por enquanto',
              text: 'Guardamos a sua busca. É assim que o Bora descobre onde falta oferta de carona.',
            ),
          if (_offers != null && _offers!.isNotEmpty) ...[
            Text(
              _offers!.length == 1 ? '1 carona encontrada' : '${_offers!.length} caronas encontradas',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            for (final o in _offers!) ...[
              _OfferCard(offer: o, onTap: () => context.push('/offer/${o.ride.id}')),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onTap});
  final RideOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = offer.ride;
    return BoraCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(formatWhen(r.departureAt),
                    style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              Text(formatCents(offer.priceCents),
                  style: const TextStyle(color: AppColors.green, fontSize: 19, fontWeight: FontWeight.w800)),
            ],
          ),
          if (r.recurringDays.isNotEmpty) Text(formatRecurring(r.recurringDays)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(child: Text(r.driver.firstName, style: const TextStyle(color: AppColors.text))),
              Text(r.seatsAvailable == 1 ? '1 vaga' : '${r.seatsAvailable} vagas'),
            ],
          ),
          const SizedBox(height: 4),
          Text(r.driver.ratingLabel),
          Text('${r.vehicle.label}, ${formatKm(offer.distanceM)} de trajeto'),
          if (offer.sharedCommunities.isNotEmpty || r.womenOnly) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in offer.sharedCommunities) Pill(c, icon: Icons.groups),
                if (r.womenOnly) const Pill('Só mulheres', icon: Icons.female, color: Color(0xFFF0ABFC)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
