import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../domain/models.dart';
import '../places/place_picker.dart';
import 'event_widgets.dart';

/// Página do evento: Ida e Volta, caronas a até 5 km de você, reservar,
/// "preciso de carona" e "vou de carro".
class EventScreen extends ConsumerStatefulWidget {
  const EventScreen({super.key, required this.eventId});
  final String eventId;
  @override
  ConsumerState<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends ConsumerState<EventScreen> {
  BoraEvent? _event;
  String _leg = 'ida';
  late Place _me = Place(label: 'Minha localização', point: ref.read(storeProvider).position);
  List<RideOffer>? _offers;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(storeProvider);
    try {
      final e = await store.event(widget.eventId);
      if (!mounted) return;
      if (e == null) {
        setState(() => _error = 'Evento não encontrado ou cancelado.');
        return;
      }
      setState(() => _event = e);
      await _loadRides();
    } catch (err) {
      if (mounted) setState(() => _error = friendlyError(err));
    }
  }

  Future<void> _loadRides() async {
    setState(() => _offers = null);
    try {
      final o = await ref.read(storeProvider).eventRides(widget.eventId, _leg, _me.point);
      if (mounted) setState(() => _offers = o);
    } catch (err) {
      if (mounted) {
        setState(() => _offers = const []);
        showBoraError(context, friendlyError(err));
      }
    }
  }

  Future<void> _changeMe() async {
    final p = await PlaceSearchScreen.open(
      context,
      title: _leg == 'ida' ? 'De onde você sai?' : 'Para onde você volta?',
      hint: 'Casa, faculdade, trabalho…',
      allowMyLocation: true,
    );
    if (p == null || !mounted) return;
    setState(() => _me = p);
    _loadRides();
  }

  Future<void> _toggleInterest() async {
    final e = _event!;
    final on = !e.myInterest.contains(_leg);
    setState(() => _busy = true);
    try {
      await ref.read(storeProvider).setEventInterest(e.id, _leg, _me.point, on);
      await _load();
      if (mounted && on) {
        showBoraError(context, 'Pronto! Motoristas indo ${_leg == 'ida' ? 'para' : 'de'} ${e.name} vão ver que você precisa.');
      }
    } catch (err) {
      if (mounted) showBoraError(context, friendlyError(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offer() async {
    final store = ref.read(storeProvider);
    if (store.myVehicles.isEmpty) {
      await context.push('/vehicle');
      if (!mounted || ref.read(storeProvider).myVehicles.isEmpty) return;
    }
    if (!mounted) return;
    await context.push('/publish?event=${widget.eventId}&leg=$_leg');
    _load();
  }

  Future<void> _book(RideOffer o) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => _ConfirmSheet(offer: o, leg: _leg, event: _event!),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(storeProvider).bookSeat(
            rideId: o.ride.id,
            pickupStopId: o.pickupStopId,
            dropoffStopId: o.dropoffStopId,
          );
      if (!mounted) return;
      await context.push('/booking/$id');
      _load();
    } catch (err) {
      if (mounted) showBoraError(context, friendlyError(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelEvent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Cancelar evento?'),
        content: const Text('O evento some da lista. As caronas já publicadas continuam valendo.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Cancelar evento')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(storeProvider).cancelEvent(widget.eventId);
      if (mounted) context.pop();
    } catch (err) {
      if (mounted) showBoraError(context, friendlyError(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: AppText.body)),
      );
    }
    final kind = eventKinds[e.kind] ?? eventKinds['outro']!;
    final wants = e.myInterest.contains(_leg);
    final offers = _offers;

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.green,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 200,
              backgroundColor: AppColors.night,
              actions: [
                if (e.isMine)
                  PopupMenuButton<String>(
                    color: AppColors.surfaceRaised,
                    onSelected: (_) => _cancelEvent(),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancelar evento'))],
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  BoraMap(
                    interactive: false,
                    center: e.point,
                    zoom: 15,
                    pins: [highlightPin('venue', e.point, e.venueLabel)],
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x880F172A), Color(0x000F172A), Color(0xFF0F172A)],
                        stops: [0, .45, 1],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xl),
              sliver: SliverList.list(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DateBadge(e.startsAt, live: e.happeningNow),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(kind.$2, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(kind.$1, style: AppText.caption),
                        if (e.communityName != null) ...[
                          const SizedBox(width: Space.xs),
                          Pill(e.communityName!, icon: Icons.groups_outlined, color: AppColors.mint),
                        ],
                      ]),
                      Text(e.name, style: AppText.headline),
                      const SizedBox(height: 2),
                      Text('${formatWhen(e.startsAt)} até ${formatTime(e.endsAt)}', style: AppText.body),
                      Text(e.venueLabel, style: AppText.body),
                    ]),
                  ),
                ]),
                if (e.meetingPoint != null) ...[
                  const SizedBox(height: Space.sm),
                  Row(children: [
                    const Icon(Icons.flag_outlined, size: 18, color: AppColors.green),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Encontro na volta: ${e.meetingPoint}', style: AppText.bodyStrong)),
                  ]),
                ],
                if (e.description.isNotEmpty) ...[
                  const SizedBox(height: Space.sm),
                  Text(e.description, style: AppText.body),
                ],
                const SizedBox(height: Space.sm),
                Row(children: [
                  Expanded(
                    child: Text('Código ${e.inviteCode} · mande no grupo da galera',
                        style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                          text: 'Bora junto pro ${e.name}! ${formatWhen(e.startsAt)} · ${e.venueLabel}. '
                              'No app Bora, em Eventos, use o código ${e.inviteCode} para achar carona.'));
                      showBoraError(context, 'Convite copiado. Cole no WhatsApp.');
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar convite'),
                  ),
                ]),
                const SizedBox(height: Space.md),
                // Ida | Volta
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'ida', label: Text('Ida · ${e.ridesIda}'), icon: const Icon(Icons.arrow_forward, size: 18)),
                    ButtonSegment(value: 'volta', label: Text('Volta · ${e.ridesVolta}'), icon: const Icon(Icons.arrow_back, size: 18)),
                  ],
                  selected: {_leg},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _leg = s.first);
                    _loadRides();
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                        (st) => st.contains(WidgetState.selected) ? AppColors.text : AppColors.surface),
                    foregroundColor: WidgetStateProperty.resolveWith(
                        (st) => st.contains(WidgetState.selected) ? AppColors.night : AppColors.text),
                    side: const WidgetStatePropertyAll(BorderSide.none),
                  ),
                ),
                const SizedBox(height: Space.sm),
                BoraCard(
                  onTap: _changeMe,
                  padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
                  child: Row(children: [
                    const Icon(Icons.my_location, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_leg == 'ida' ? 'Saindo de' : 'Voltando para', style: AppText.caption),
                        Text(_me.label, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    const Text('Mudar', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: Space.xs),
                Text('Caronas que passam a até 5 km de você.', style: AppText.caption),
                const SizedBox(height: Space.sm),
                if (offers == null)
                  const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
                else if (offers.isEmpty)
                  EmptyState(
                    icon: Icons.directions_car_outlined,
                    title: _leg == 'ida' ? 'Ninguém indo da sua região ainda' : 'Ninguém voltando para sua região ainda',
                    text: 'Marque que precisa de carona: quem for de carro vê quantas pessoas estão procurando no caminho.',
                  )
                else
                  for (final o in offers) ...[
                    _EventOfferCard(offer: o, leg: _leg, onTap: _busy ? null : () => _book(o)),
                    const SizedBox(height: Space.xs),
                  ],
                const SizedBox(height: Space.md),
                BoraButton(
                  label: wants ? 'Você está na lista de quem precisa' : 'Preciso de carona (${_leg == 'ida' ? 'ida' : 'volta'})',
                  icon: wants ? Icons.check : Icons.front_hand_outlined,
                  kind: wants ? BoraButtonKind.secondary : BoraButtonKind.primary,
                  loading: _busy,
                  onPressed: _toggleInterest,
                ),
                if (wants)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xxs),
                    child: Text('Toque de novo para sair da lista.', style: AppText.caption, textAlign: TextAlign.center),
                  ),
                const SizedBox(height: Space.sm),
                BoraButton(
                  label: _leg == 'ida' ? 'Vou de carro e tenho vaga' : 'Volto de carro e tenho vaga',
                  icon: Icons.directions_car_outlined,
                  kind: BoraButtonKind.ghost,
                  onPressed: _offer,
                ),
                if (e.interested > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text('${e.interested} ${e.interested == 1 ? 'pessoa procurando' : 'pessoas procurando'} carona para este evento.',
                        style: AppText.caption, textAlign: TextAlign.center),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventOfferCard extends StatelessWidget {
  const _EventOfferCard({required this.offer, required this.leg, required this.onTap});
  final RideOffer offer;
  final String leg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = offer.ride;
    final near = leg == 'ida' ? offer.pickup : offer.dropoff;
    final nearM = leg == 'ida' ? offer.pickupWalkM : offer.dropoffWalkM;
    return BoraCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(r.driver.initial),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.driver.firstName} · ${r.vehicle.model}', style: AppText.bodyStrong),
              Text('${r.seatsAvailable} ${r.seatsAvailable == 1 ? 'vaga' : 'vagas'} · ★ ${r.driver.ratingLabel}', style: AppText.caption),
            ]),
          ),
          Metric(value: formatCents(offer.priceCents), label: 'rateio', alignEnd: true),
        ]),
        const SizedBox(height: Space.sm),
        Row(children: [
          Icon(leg == 'ida' ? Icons.directions_bus_outlined : Icons.flag_outlined, size: 16, color: AppColors.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              leg == 'ida'
                  ? 'Embarque em ${near?.name ?? 'parada'} às ${offer.pickupEta == null ? '--' : formatTime(offer.pickupEta!)}'
                  : 'Saída às ${offer.pickupEta == null ? '--' : formatTime(offer.pickupEta!)} · desce em ${near?.name ?? 'parada'}',
              style: AppText.body.copyWith(color: AppColors.text),
            ),
          ),
        ]),
        if (nearM != null)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2),
            child: Text(
              nearM < 1000 ? '$nearM m de você' : '${formatKm(nearM)} de você',
              style: AppText.caption,
            ),
          ),
      ]),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.offer, required this.leg, required this.event});
  final RideOffer offer;
  final String leg;
  final BoraEvent event;

  @override
  Widget build(BuildContext context) {
    final r = offer.ride;
    final pickupWhen = offer.pickupEta == null ? '--' : formatTime(offer.pickupEta!);
    final beThere = offer.beThereBy == null ? pickupWhen : formatTime(offer.beThereBy!);
    final day = offer.pickupEta == null ? '' : '${weekdayShort(offer.pickupEta!.weekday)} ${offer.pickupEta!.day}/${offer.pickupEta!.month}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(leg == 'ida' ? 'Reservar ida' : 'Reservar volta', style: AppText.headline.copyWith(fontSize: 22))),
              Metric(value: formatCents(offer.priceCents), label: 'rateio sugerido', alignEnd: true),
            ]),
            const SizedBox(height: Space.md),
            BoraCard(
              highlight: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(leg == 'ida' ? 'Esteja no ponto de embarque' : 'Encontro na saída do evento', style: AppText.subtitle),
                const SizedBox(height: Space.xs),
                Text(leg == 'ida' ? (offer.pickup?.name ?? '') : (event.meetingPoint ?? offer.pickup?.name ?? event.venueLabel),
                    style: AppText.bodyStrong),
                Text('$day · até $beThere · o carro passa às $pickupWhen', style: AppText.body),
                if (leg == 'ida' && (offer.pickupWalkM ?? 0) > 1000)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xs),
                    child: Text('É um pouco longe de você: dá tempo de se programar para chegar lá (a pé, de ônibus ou de app).',
                        style: AppText.caption),
                  ),
                if (leg == 'volta')
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xs),
                    child: Text('O horário da volta pode mudar com o fim do evento. O motorista confirma no dia.', style: AppText.caption),
                  ),
              ]),
            ),
            const SizedBox(height: Space.sm),
            RouteSummary(
              from: offer.pickup?.name ?? 'Embarque',
              to: leg == 'ida' ? event.venueLabel : (offer.dropoff?.name ?? 'Desembarque'),
              toDetail: offer.dropoffEta == null ? null : 'Chegada por volta das ${formatTime(offer.dropoffEta!)}',
            ),
            const SizedBox(height: Space.md),
            Row(children: [
              Avatar(r.driver.initial),
              const SizedBox(width: Space.sm),
              Expanded(child: Text('${r.driver.firstName} · ${r.vehicle.brand} ${r.vehicle.model} ${r.vehicle.color}', style: AppText.body)),
            ]),
            const SizedBox(height: Space.md),
            BoraButton(label: 'Reservar vaga', onPressed: () => Navigator.of(context).pop(true)),
          ],
        ),
      ),
    );
  }
}
